//
//  GLFrame.swift
//  KivyRepresentable
//
//  The recording side of `KivyGL`: one command buffer, begun by the first
//  call that needs the GPU and submitted (and waited for) at the end of
//  Kivy's frame, or when GL has to give something back. Everything a frame
//  hands the GPU — vertices, indices, uniform blocks, texture uploads — is
//  written into one host-visible streaming buffer, so a draw sees its data
//  exactly as it was when the draw was issued, the way GL promises.
//
//  The GPU work is waited for at submit, so nothing in flight ever outlives
//  a frame: the streaming buffer and descriptor pools simply start over, and
//  a retired image is destroyed right after.
//

@preconcurrency import CVulkan

/// Framebuffer images and the Vulkan objects that render into them.
struct GLRenderTarget {
    let color: GLImage
    let depthStencil: GLImage?
    let framebuffer: VkFramebuffer
    let renderPass: VkRenderPass
    var width: Int { color.width }
    var height: Int { color.height }
}

final class GLFrame {
    unowned let device: KivyGLDevice
    let commandBuffer: VkCommandBuffer
    private let fence: VkFence

    private(set) var recording = false
    /// The framebuffer of the render pass being recorded, if one is.
    private(set) var activePass: VkFramebuffer?

    let arena: GLStreamArena
    private var descriptorPools: [VkDescriptorPool] = []
    private var poolIndex = 0
    private var retired: [() -> Void] = []
    /// GL buffer versions already in the arena this frame.
    var uploadedBuffers: [Int: (buffer: VkBuffer, offset: Int)] = [:]
    private var renderPasses: [String: VkRenderPass] = [:]

    init(device: KivyGLDevice) throws {
        self.device = device
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.commandPool = device.commandPool
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandBufferCount = 1
        var cmd: VkCommandBuffer?
        guard vkAllocateCommandBuffers(device.device, &allocInfo, &cmd) == VK_SUCCESS, let cmd else {
            throw KivyGLError.commandPool
        }
        self.commandBuffer = cmd
        var fenceInfo = VkFenceCreateInfo()
        fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
        var fence: VkFence?
        guard vkCreateFence(device.device, &fenceInfo, nil, &fence) == VK_SUCCESS, let fence else {
            throw KivyGLError.commandPool
        }
        self.fence = fence
        self.arena = GLStreamArena(device: device)
    }

    // MARK: - Recording

    /// The command buffer, begun if this is the frame's first command.
    @discardableResult
    func begin() -> VkCommandBuffer {
        if !recording {
            vkResetCommandBuffer(commandBuffer, 0)
            var info = VkCommandBufferBeginInfo()
            info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
            info.flags = VkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)
            vkBeginCommandBuffer(commandBuffer, &info)
            recording = true
        }
        return commandBuffer
    }

    /// Submit what has been recorded and wait for it, then start every
    /// per-frame resource over.
    func submit() {
        guard recording else { return }
        endPass()
        vkEndCommandBuffer(commandBuffer)
        var cmd: VkCommandBuffer? = commandBuffer
        withUnsafePointer(to: &cmd) { cmdPtr in
            var info = VkSubmitInfo()
            info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
            info.commandBufferCount = 1
            info.pCommandBuffers = cmdPtr
            _ = vkQueueSubmit(device.queue, 1, &info, self.fence)
        }
        var waitFence: VkFence? = fence
        vkWaitForFences(device.device, 1, &waitFence, VK_TRUE, UInt64.max)
        vkResetFences(device.device, 1, &waitFence)
        recording = false
        arena.reset()
        for pool in descriptorPools { vkResetDescriptorPool(device.device, pool, 0) }
        poolIndex = 0
        uploadedBuffers.removeAll(keepingCapacity: true)
        let release = retired
        retired.removeAll()
        release.forEach { $0() }
    }

    /// Run `release` once nothing recorded so far can still use what it
    /// frees.
    func retire(_ release: @escaping () -> Void) {
        if recording {
            retired.append(release)
        } else {
            release()
        }
    }

    func finish() {
        submit()
        vkDeviceWaitIdle(device.device)
    }

    func destroy() {
        arena.destroy()
        for pool in descriptorPools { vkDestroyDescriptorPool(device.device, pool, nil) }
        for pass in renderPasses.values { vkDestroyRenderPass(device.device, pass, nil) }
        vkDestroyFence(device.device, fence, nil)
        var cmd: VkCommandBuffer? = commandBuffer
        vkFreeCommandBuffers(device.device, device.commandPool, 1, &cmd)
    }

    // MARK: - Render passes

    func beginPass(_ target: GLRenderTarget) {
        if activePass == target.framebuffer { return }
        endPass()
        let cmd = begin()
        transition(target.color, to: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
        if let depthStencil = target.depthStencil {
            transition(depthStencil, to: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
        }
        var info = VkRenderPassBeginInfo()
        info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
        info.renderPass = target.renderPass
        info.framebuffer = target.framebuffer
        info.renderArea = VkRect2D(
            offset: VkOffset2D(x: 0, y: 0),
            extent: VkExtent2D(width: UInt32(target.width), height: UInt32(target.height))
        )
        vkCmdBeginRenderPass(cmd, &info, VK_SUBPASS_CONTENTS_INLINE)
        activePass = target.framebuffer
    }

    func endPass() {
        guard activePass != nil else { return }
        vkCmdEndRenderPass(commandBuffer)
        activePass = nil
    }

    /// Load-and-store, starting and ending in the attachment layouts: every
    /// pass picks up where GL left the framebuffer, and the transitions in
    /// and out are explicit barriers.
    func renderPass(color: VkFormat, depthStencil: VkFormat?) throws -> VkRenderPass {
        let key = "\(color.rawValue)-\(depthStencil?.rawValue ?? 0)"
        if let pass = renderPasses[key] { return pass }

        var attachments = [VkAttachmentDescription()]
        attachments[0].format = color
        attachments[0].samples = VK_SAMPLE_COUNT_1_BIT
        attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_LOAD
        attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE
        attachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE
        attachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE
        attachments[0].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        attachments[0].finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        if let depthStencil {
            var ds = VkAttachmentDescription()
            ds.format = depthStencil
            ds.samples = VK_SAMPLE_COUNT_1_BIT
            ds.loadOp = VK_ATTACHMENT_LOAD_OP_LOAD
            ds.storeOp = VK_ATTACHMENT_STORE_OP_STORE
            ds.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_LOAD
            ds.stencilStoreOp = VK_ATTACHMENT_STORE_OP_STORE
            ds.initialLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            ds.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            attachments.append(ds)
        }
        var colorRef = VkAttachmentReference(attachment: 0, layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
        var dsRef = VkAttachmentReference(attachment: 1, layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
        var created: VkRenderPass?
        let result = withUnsafePointer(to: &colorRef) { colorPtr in
            withUnsafePointer(to: &dsRef) { dsPtr in
                var subpass = VkSubpassDescription()
                subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS
                subpass.colorAttachmentCount = 1
                subpass.pColorAttachments = colorPtr
                subpass.pDepthStencilAttachment = depthStencil != nil ? dsPtr : nil
                return withUnsafePointer(to: &subpass) { subpassPtr in
                    attachments.withUnsafeBufferPointer { attachmentsPtr in
                        var info = VkRenderPassCreateInfo()
                        info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
                        info.attachmentCount = UInt32(attachmentsPtr.count)
                        info.pAttachments = attachmentsPtr.baseAddress
                        info.subpassCount = 1
                        info.pSubpasses = subpassPtr
                        return vkCreateRenderPass(device.device, &info, nil, &created)
                    }
                }
            }
        }
        guard result == VK_SUCCESS, let created else { throw KivyGLError.image }
        renderPasses[key] = created
        return created
    }

    // MARK: - Barriers

    /// Move `image` to `layout`, waiting for whatever last used it. A
    /// barrier is recorded even for the same layout when that layout writes:
    /// two uploads to one texture, or two passes into one framebuffer, must
    /// not overlap.
    func transition(_ image: GLImage, to layout: VkImageLayout) {
        if image.layout == layout && layout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL { return }
        let cmd = begin()
        let source = Self.usage(of: image.layout)
        let destination = Self.usage(of: layout)
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.srcAccessMask = source.access
        barrier.dstAccessMask = destination.access
        barrier.oldLayout = image.layout
        barrier.newLayout = layout
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image.image
        barrier.subresourceRange = VkImageSubresourceRange(
            aspectMask: image.aspect, baseMipLevel: 0, levelCount: UInt32(image.levels), baseArrayLayer: 0, layerCount: 1
        )
        vkCmdPipelineBarrier(cmd, source.stage, destination.stage, 0, 0, nil, 0, nil, 1, &barrier)
        image.layout = layout
    }

    static func usage(of layout: VkImageLayout) -> (access: VkAccessFlags, stage: VkPipelineStageFlags) {
        switch layout {
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            return (VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue), VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue))
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            return (VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue), VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue))
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            return (
                VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
                VkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_SHADER_BIT.rawValue | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
            )
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            return (
                VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_READ_BIT.rawValue | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue),
                VkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue)
            )
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            return (
                VkAccessFlags(VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT.rawValue | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT.rawValue),
                VkPipelineStageFlags(VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT.rawValue | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT.rawValue)
            )
        default:
            return (0, VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue))
        }
    }

    // MARK: - Descriptor sets

    func allocateSet(_ layout: VkDescriptorSetLayout) throws -> VkDescriptorSet {
        while true {
            if poolIndex == descriptorPools.count {
                descriptorPools.append(try makePool())
            }
            var layoutOpt: VkDescriptorSetLayout? = layout
            var set: VkDescriptorSet?
            let result = withUnsafePointer(to: &layoutOpt) { layoutPtr in
                var info = VkDescriptorSetAllocateInfo()
                info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
                info.descriptorPool = descriptorPools[poolIndex]
                info.descriptorSetCount = 1
                info.pSetLayouts = layoutPtr
                return vkAllocateDescriptorSets(device.device, &info, &set)
            }
            if result == VK_SUCCESS, let set { return set }
            poolIndex += 1
        }
    }

    private func makePool() throws -> VkDescriptorPool {
        var sizes = [
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1024),
            VkDescriptorPoolSize(type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, descriptorCount: 4096),
        ]
        var info = VkDescriptorPoolCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        info.maxSets = 1024
        info.poolSizeCount = UInt32(sizes.count)
        var pool: VkDescriptorPool?
        let result = sizes.withUnsafeMutableBufferPointer { sizesPtr in
            info.pPoolSizes = UnsafePointer(sizesPtr.baseAddress)
            return vkCreateDescriptorPool(device.device, &info, nil, &pool)
        }
        guard result == VK_SUCCESS, let pool else { throw KivyGLError.memory }
        return pool
    }
}

/// Host-visible, mapped buffers handed out front to back and started over
/// every frame.
final class GLStreamArena {
    private struct Chunk {
        let buffer: VkBuffer
        let memory: VkDeviceMemory
        let mapped: UnsafeMutableRawPointer
        let size: Int
    }

    unowned let device: KivyGLDevice
    private var chunks: [Chunk] = []
    private var current = 0
    private var offset = 0
    private static let chunkSize = 4 << 20

    init(device: KivyGLDevice) {
        self.device = device
    }

    /// `size` bytes at `alignment`, valid until the frame is submitted.
    func allocate(_ size: Int, alignment: Int = 16) throws -> (buffer: VkBuffer, offset: Int, pointer: UnsafeMutableRawPointer) {
        let size = max(size, 1)
        while current < chunks.count {
            let aligned = (offset + alignment - 1) / alignment * alignment
            if aligned + size <= chunks[current].size {
                offset = aligned + size
                let chunk = chunks[current]
                return (chunk.buffer, aligned, chunk.mapped.advanced(by: aligned))
            }
            current += 1
            offset = 0
        }
        let chunk = try makeChunk(max(Self.chunkSize, size))
        chunks.append(chunk)
        current = chunks.count - 1
        offset = size
        return (chunk.buffer, 0, chunk.mapped)
    }

    /// Copy `bytes` in.
    func upload(_ bytes: UnsafeRawBufferPointer, alignment: Int = 16) throws -> (buffer: VkBuffer, offset: Int) {
        let slot = try allocate(bytes.count, alignment: alignment)
        if let base = bytes.baseAddress, bytes.count > 0 {
            slot.pointer.copyMemory(from: base, byteCount: bytes.count)
        }
        return (slot.buffer, slot.offset)
    }

    func reset() {
        current = 0
        offset = 0
    }

    func destroy() {
        for chunk in chunks {
            vkUnmapMemory(device.device, chunk.memory)
            vkDestroyBuffer(device.device, chunk.buffer, nil)
            vkFreeMemory(device.device, chunk.memory, nil)
        }
        chunks.removeAll()
    }

    private func makeChunk(_ size: Int) throws -> Chunk {
        var info = VkBufferCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        info.size = VkDeviceSize(size)
        info.usage = VkBufferUsageFlags(
            VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue | VK_BUFFER_USAGE_INDEX_BUFFER_BIT.rawValue
                | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue | VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue
                | VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue
        )
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        var buffer: VkBuffer?
        guard vkCreateBuffer(device.device, &info, nil, &buffer) == VK_SUCCESS, let buffer else {
            throw KivyGLError.buffer
        }
        var requirements = VkMemoryRequirements()
        vkGetBufferMemoryRequirements(device.device, buffer, &requirements)
        let memory = try device.allocate(
            requirements,
            properties: VkMemoryPropertyFlags(
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
            )
        )
        vkBindBufferMemory(device.device, buffer, memory, 0)
        var mapped: UnsafeMutableRawPointer?
        vkMapMemory(device.device, memory, 0, VkDeviceSize(size), 0, &mapped)
        guard let mapped else { throw KivyGLError.memory }
        return Chunk(buffer: buffer, memory: memory, mapped: mapped, size: size)
    }
}
