//
//  KivyGL+Draw.swift
//  KivyRepresentable
//
//  glDrawArrays / glDrawElements: GL's current state turned into a Vulkan
//  pipeline (made once per distinct state and kept), the draw's vertices,
//  indices and uniform block copied into the frame's streaming buffer, and
//  the draw recorded into the bound framebuffer's render pass.
//
//  GL_TRIANGLE_FAN and GL_LINE_LOOP — Kivy's Mesh and Line use both — are
//  drawn as triangle lists and line strips with indices made here: MoltenVK
//  has no fans, and Vulkan has no loops.
//

import Foundation
@preconcurrency import CVulkan

/// Everything a pipeline is made from. Viewport, scissor, stencil masks
/// and reference, and the blend color are dynamic, so they are not in it.
struct GLPipelineKey: Hashable {
    struct Input: Hashable {
        let location: UInt32
        let format: UInt32
        let stride: UInt32
        let perInstance: Bool
    }

    let program: Int
    let generation: Int
    let renderPass: Int
    let topology: UInt32
    let inputs: [Input]
    let blend: Bool
    let blendFactors: [GLenum]
    let blendEquations: [GLenum]
    let colorMask: UInt8
    let depthTest: Bool
    let depthWrite: Bool
    let depthFunc: GLenum
    let stencilTest: Bool
    let stencilOps: [GLenum]
    let cull: GLenum
    let frontFace: GLenum
}

extension KivyGL {

    func drawArrays(_ mode: GLenum, _ first: GLint, _ count: GLsizei) {
        guard first >= 0, count >= 0 else { return setError(GL.invalidValue) }
        guard count > 0 else { return }
        switch mode {
        case GL.triangleFan, GL.lineLoop:
            let indices = (0..<UInt32(count)).map { UInt32(first) + $0 }
            draw(mode, indices: convert(indices, mode: mode))
        default:
            draw(mode, indices: nil, vertexCount: Int(count), firstVertex: Int(first))
        }
    }

    func drawElements(_ mode: GLenum, _ count: GLsizei, _ type: GLenum, _ offsetPointer: UnsafeRawPointer?) {
        guard count >= 0 else { return setError(GL.invalidValue) }
        guard count > 0 else { return }
        guard let buffer = buffers[elementArrayBuffer] else {
            // Client-side index arrays: Kivy always has an element buffer.
            return setError(GL.invalidOperation)
        }
        let offset = Int(bitPattern: offsetPointer)
        let size: Int
        switch type {
        case GL.unsignedByte: size = 1
        case GL.unsignedShort: size = 2
        case GL.unsignedInt: size = 4
        default: return setError(GL.invalidEnum)
        }
        guard offset >= 0, offset + Int(count) * size <= buffer.data.count else { return setError(GL.invalidOperation) }
        let indices: [UInt32] = buffer.data.withUnsafeBytes { bytes in
            (0..<Int(count)).map { index in
                switch size {
                case 1: UInt32(bytes[offset + index])
                case 2: UInt32(bytes.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self))
                default: bytes.loadUnaligned(fromByteOffset: offset + index * 4, as: UInt32.self)
                }
            }
        }
        draw(mode, indices: convert(indices, mode: mode))
    }

    private func convert(_ indices: [UInt32], mode: GLenum) -> [UInt32] {
        switch mode {
        case GL.triangleFan:
            guard indices.count >= 3 else { return [] }
            var out: [UInt32] = []
            out.reserveCapacity((indices.count - 2) * 3)
            for i in 1..<(indices.count - 1) {
                out.append(indices[0]); out.append(indices[i]); out.append(indices[i + 1])
            }
            return out
        case GL.lineLoop:
            guard indices.count >= 2 else { return [] }
            return indices + [indices[0]]
        default:
            return indices
        }
    }

    private func topology(_ mode: GLenum) -> VkPrimitiveTopology? {
        switch mode {
        case GL.points: VK_PRIMITIVE_TOPOLOGY_POINT_LIST
        case GL.lines: VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        case GL.lineStrip, GL.lineLoop: VK_PRIMITIVE_TOPOLOGY_LINE_STRIP
        case GL.triangles, GL.triangleFan: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        case GL.triangleStrip: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
        default: nil
        }
    }

    // MARK: - The draw

    private func draw(_ mode: GLenum, indices: [UInt32]?, vertexCount: Int = 0, firstVertex: Int = 0) {
        guard let topology = topology(mode) else { return setError(GL.invalidEnum) }
        if let indices, indices.isEmpty { return }
        guard let program = programs[currentProgram], program.linked,
              let pipelineLayout = program.pipelineLayout, let setLayout = program.setLayout
        else { return setError(GL.invalidOperation) }
        guard let target = currentTarget() else { return setError(GL.invalidFramebufferOperation) }
        guard let scissor = clipRect(in: target) else { return }

        // Sampled images go to SHADER_READ_ONLY outside the render pass.
        var images: [(binding: Int, element: Int, image: GLImage, sampler: VkSampler)] = []
        for uniform in program.uniforms {
            guard let binding = uniform.binding, let units = program.samplerUnits[binding] else { continue }
            for (element, unit) in units.enumerated() {
                let texture = unit < Self.maxTextureUnits ? textures[textureUnits[unit]] : nil
                let image = texture?.image ?? blankTexture()
                guard let image, let sampler = sampler(for: texture ?? GLTexture(), levels: image.levels) else {
                    return setError(GL.outOfMemory)
                }
                images.append((binding, element, image, sampler))
            }
        }
        let attachments = [target.color, target.depthStencil].compactMap { $0 }
        if images.contains(where: { entry in entry.image.layout != VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL && !attachments.contains { $0 === entry.image } }) {
            frame.endPass()
            for entry in images where !attachments.contains(where: { $0 === entry.image }) {
                frame.transition(entry.image, to: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
            }
        }

        do {
            // Vertex inputs, one binding per location.
            var inputs: [GLPipelineKey.Input] = []
            var vertexBuffers: [(binding: UInt32, buffer: VkBuffer, offset: Int)] = []
            for attribute in program.attributes {
                for column in 0..<(attribute.variable.type.locations * attribute.variable.count) {
                    let location = attribute.location + column
                    let state = vertexAttributes[location]
                    if state.enabled {
                        guard let buffer = buffers[state.buffer] else { return setError(GL.invalidOperation) }
                        guard let format = vertexFormat(size: Int(state.size), type: state.type, normalized: state.normalized) else {
                            return setError(GL.invalidEnum)
                        }
                        let uploaded = try upload(buffer)
                        let stride = state.stride != 0 ? Int(state.stride) : Int(state.size) * componentSize(state.type)
                        inputs.append(.init(location: UInt32(location), format: format.rawValue, stride: UInt32(stride), perInstance: false))
                        vertexBuffers.append((UInt32(location), uploaded.buffer, uploaded.offset + state.offset))
                    } else {
                        var value = state.current
                        let uploaded = try withUnsafeBytes(of: &value) { try frame.arena.upload($0) }
                        inputs.append(.init(location: UInt32(location), format: VK_FORMAT_R32G32B32A32_SFLOAT.rawValue, stride: 16, perInstance: true))
                        vertexBuffers.append((UInt32(location), uploaded.buffer, uploaded.offset))
                    }
                }
            }

            let set = try frame.allocateSet(setLayout)
            try writeDescriptors(set, program: program, images: images)

            guard let pipeline = try pipeline(program: program, target: target, topology: topology, inputs: inputs) else {
                return setError(GL.outOfMemory)
            }

            var indexBuffer: (buffer: VkBuffer, offset: Int, type: VkIndexType)?
            if let indices {
                // Metal restarts strips at 0xFFFF and can't be told not to, so
                // 16-bit indices stop below it.
                if indices.max()! < UInt32(UInt16.max) {
                    let shorts = indices.map { UInt16($0) }
                    let uploaded = try shorts.withUnsafeBytes { try frame.arena.upload($0, alignment: 4) }
                    indexBuffer = (uploaded.buffer, uploaded.offset, VK_INDEX_TYPE_UINT16)
                } else {
                    let uploaded = try indices.withUnsafeBytes { try frame.arena.upload($0, alignment: 4) }
                    indexBuffer = (uploaded.buffer, uploaded.offset, VK_INDEX_TYPE_UINT32)
                }
            }

            frame.beginPass(target)
            let cmd = frame.commandBuffer
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
            var setOpt: VkDescriptorSet? = set
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &setOpt, 0, nil)
            for entry in vertexBuffers {
                var buffer: VkBuffer? = entry.buffer
                var offset = VkDeviceSize(entry.offset)
                vkCmdBindVertexBuffers(cmd, entry.binding, 1, &buffer, &offset)
            }
            var viewport = VkViewport(
                x: Float(self.viewport.x), y: Float(self.viewport.y),
                width: Float(max(1, self.viewport.width)), height: Float(max(1, self.viewport.height)),
                minDepth: 0, maxDepth: 1
            )
            vkCmdSetViewport(cmd, 0, 1, &viewport)
            var scissorRect = scissor
            vkCmdSetScissor(cmd, 0, 1, &scissorRect)
            let front = VkStencilFaceFlags(VK_STENCIL_FACE_FRONT_BIT.rawValue)
            let back = VkStencilFaceFlags(VK_STENCIL_FACE_BACK_BIT.rawValue)
            vkCmdSetStencilCompareMask(cmd, front, stencil.front.valueMask)
            vkCmdSetStencilCompareMask(cmd, back, stencil.back.valueMask)
            vkCmdSetStencilWriteMask(cmd, front, stencil.front.writeMask)
            vkCmdSetStencilWriteMask(cmd, back, stencil.back.writeMask)
            vkCmdSetStencilReference(cmd, front, UInt32(truncatingIfNeeded: stencil.front.reference))
            vkCmdSetStencilReference(cmd, back, UInt32(truncatingIfNeeded: stencil.back.reference))
            var constants = (blendColor.x, blendColor.y, blendColor.z, blendColor.w)
            withUnsafePointer(to: &constants) { ptr in
                ptr.withMemoryRebound(to: Float.self, capacity: 4) { vkCmdSetBlendConstants(cmd, $0) }
            }

            if let indices, let indexBuffer {
                vkCmdBindIndexBuffer(cmd, indexBuffer.buffer, VkDeviceSize(indexBuffer.offset), indexBuffer.type)
                vkCmdDrawIndexed(cmd, UInt32(indices.count), 1, 0, 0, 0)
            } else {
                vkCmdDraw(cmd, UInt32(vertexCount), 1, UInt32(firstVertex), 0)
            }
        } catch {
            setError(GL.outOfMemory)
        }
    }

    /// The buffer's bytes in the arena, once per frame per version.
    private func upload(_ buffer: GLBuffer) throws -> (buffer: VkBuffer, offset: Int) {
        if let cached = frame.uploadedBuffers[buffer.version] { return cached }
        let uploaded = try buffer.data.withUnsafeBytes { try frame.arena.upload($0) }
        frame.uploadedBuffers[buffer.version] = uploaded
        return uploaded
    }

    private func writeDescriptors(
        _ set: VkDescriptorSet, program: GLProgram,
        images: [(binding: Int, element: Int, image: GLImage, sampler: VkSampler)]
    ) throws {
        var bufferInfo = VkDescriptorBufferInfo()
        if program.blockSize > 0 {
            let alignment = max(16, Int(device.limits.minUniformBufferOffsetAlignment))
            let uploaded = try program.blockData.withUnsafeBytes { try frame.arena.upload($0, alignment: alignment) }
            bufferInfo = VkDescriptorBufferInfo(buffer: uploaded.buffer, offset: VkDeviceSize(uploaded.offset), range: VkDeviceSize(program.blockSize))
        }
        var imageInfos = images.map {
            VkDescriptorImageInfo(sampler: $0.sampler, imageView: $0.image.view, imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
        }
        withUnsafePointer(to: &bufferInfo) { bufferPtr in
            imageInfos.withUnsafeMutableBufferPointer { imagePtr in
                var writes: [VkWriteDescriptorSet] = []
                if program.blockSize > 0 {
                    var write = VkWriteDescriptorSet()
                    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                    write.dstSet = set
                    write.dstBinding = 0
                    write.descriptorCount = 1
                    write.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
                    write.pBufferInfo = bufferPtr
                    writes.append(write)
                }
                for (index, entry) in images.enumerated() {
                    var write = VkWriteDescriptorSet()
                    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
                    write.dstSet = set
                    write.dstBinding = UInt32(entry.binding)
                    write.dstArrayElement = UInt32(entry.element)
                    write.descriptorCount = 1
                    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
                    write.pImageInfo = UnsafePointer(imagePtr.baseAddress! + index)
                    writes.append(write)
                }
                writes.withUnsafeBufferPointer { writesPtr in
                    vkUpdateDescriptorSets(device.device, UInt32(writesPtr.count), writesPtr.baseAddress, 0, nil)
                }
            }
        }
    }

    // MARK: - Formats

    private func componentSize(_ type: GLenum) -> Int {
        switch type {
        case GL.byte, GL.unsignedByte: 1
        case GL.short, GL.unsignedShort: 2
        default: 4
        }
    }

    private func vertexFormat(size: Int, type: GLenum, normalized: Bool) -> VkFormat? {
        let formats: [VkFormat]
        switch (type, normalized) {
        case (GL.float, _):
            formats = [VK_FORMAT_R32_SFLOAT, VK_FORMAT_R32G32_SFLOAT, VK_FORMAT_R32G32B32_SFLOAT, VK_FORMAT_R32G32B32A32_SFLOAT]
        case (GL.unsignedByte, true):
            formats = [VK_FORMAT_R8_UNORM, VK_FORMAT_R8G8_UNORM, VK_FORMAT_R8G8B8_UNORM, VK_FORMAT_R8G8B8A8_UNORM]
        case (GL.unsignedByte, false):
            formats = [VK_FORMAT_R8_USCALED, VK_FORMAT_R8G8_USCALED, VK_FORMAT_R8G8B8_USCALED, VK_FORMAT_R8G8B8A8_USCALED]
        case (GL.byte, true):
            formats = [VK_FORMAT_R8_SNORM, VK_FORMAT_R8G8_SNORM, VK_FORMAT_R8G8B8_SNORM, VK_FORMAT_R8G8B8A8_SNORM]
        case (GL.byte, false):
            formats = [VK_FORMAT_R8_SSCALED, VK_FORMAT_R8G8_SSCALED, VK_FORMAT_R8G8B8_SSCALED, VK_FORMAT_R8G8B8A8_SSCALED]
        case (GL.unsignedShort, true):
            formats = [VK_FORMAT_R16_UNORM, VK_FORMAT_R16G16_UNORM, VK_FORMAT_R16G16B16_UNORM, VK_FORMAT_R16G16B16A16_UNORM]
        case (GL.unsignedShort, false):
            formats = [VK_FORMAT_R16_USCALED, VK_FORMAT_R16G16_USCALED, VK_FORMAT_R16G16B16_USCALED, VK_FORMAT_R16G16B16A16_USCALED]
        case (GL.short, true):
            formats = [VK_FORMAT_R16_SNORM, VK_FORMAT_R16G16_SNORM, VK_FORMAT_R16G16B16_SNORM, VK_FORMAT_R16G16B16A16_SNORM]
        case (GL.short, false):
            formats = [VK_FORMAT_R16_SSCALED, VK_FORMAT_R16G16_SSCALED, VK_FORMAT_R16G16B16_SSCALED, VK_FORMAT_R16G16B16A16_SSCALED]
        default:
            return nil
        }
        return (1...4).contains(size) ? formats[size - 1] : nil
    }

    // MARK: - Pipelines

    private func pipeline(program: GLProgram, target: GLRenderTarget, topology: VkPrimitiveTopology, inputs: [GLPipelineKey.Input]) throws -> VkPipeline? {
        let hasDepthStencil = target.depthStencil != nil
        let key = GLPipelineKey(
            program: program.serial,
            generation: program.generation,
            renderPass: Int(bitPattern: UnsafeRawPointer(target.renderPass)),
            topology: topology.rawValue,
            inputs: inputs,
            blend: blend,
            blendFactors: blend ? [blendSource.rgb, blendDestination.rgb, blendSource.alpha, blendDestination.alpha] : [],
            blendEquations: blend ? [blendEquation.rgb, blendEquation.alpha] : [],
            colorMask: (colorMask.0 ? 1 : 0) | (colorMask.1 ? 2 : 0) | (colorMask.2 ? 4 : 0) | (colorMask.3 ? 8 : 0),
            depthTest: depthTest && hasDepthStencil,
            depthWrite: depthMask && depthTest && hasDepthStencil,
            depthFunc: depthTest && hasDepthStencil ? depthFunc : GL.always,
            stencilTest: stencilTest && hasDepthStencil,
            stencilOps: stencilTest && hasDepthStencil ? [
                stencil.front.function, stencil.front.fail, stencil.front.depthFail, stencil.front.pass,
                stencil.back.function, stencil.back.fail, stencil.back.depthFail, stencil.back.pass,
            ] : [],
            cull: cullFace ? cullFaceMode : GL.`none`,
            frontFace: frontFace
        )
        if let pipeline = pipelines[key] { return pipeline }
        guard let vertexModule = program.vertexModule, let fragmentModule = program.fragmentModule,
              let layout = program.pipelineLayout
        else { return nil }

        let main = strdup("main")!
        defer { free(main) }
        var stages = [VkPipelineShaderStageCreateInfo(), VkPipelineShaderStageCreateInfo()]
        stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT
        stages[0].module = vertexModule
        stages[0].pName = UnsafePointer(main)
        stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT
        stages[1].module = fragmentModule
        stages[1].pName = UnsafePointer(main)

        let bindings = inputs.map {
            VkVertexInputBindingDescription(
                binding: $0.location, stride: $0.stride,
                inputRate: $0.perInstance ? VK_VERTEX_INPUT_RATE_INSTANCE : VK_VERTEX_INPUT_RATE_VERTEX
            )
        }
        let attributes = inputs.map {
            VkVertexInputAttributeDescription(location: $0.location, binding: $0.location, format: VkFormat(rawValue: $0.format), offset: 0)
        }

        var assembly = VkPipelineInputAssemblyStateCreateInfo()
        assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
        assembly.topology = topology

        var viewportState = VkPipelineViewportStateCreateInfo()
        viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewportState.viewportCount = 1
        viewportState.scissorCount = 1

        var raster = VkPipelineRasterizationStateCreateInfo()
        raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
        raster.polygonMode = VK_POLYGON_MODE_FILL
        raster.lineWidth = 1
        switch key.cull {
        case GL.front: raster.cullMode = VkCullModeFlags(VK_CULL_MODE_FRONT_BIT.rawValue)
        case GL.back: raster.cullMode = VkCullModeFlags(VK_CULL_MODE_BACK_BIT.rawValue)
        case GL.frontAndBack: raster.cullMode = VkCullModeFlags(VK_CULL_MODE_FRONT_AND_BACK.rawValue)
        default: raster.cullMode = 0
        }
        // GL's and Vulkan's window y count the same rows here (nothing is
        // flipped), but Vulkan's signed-area formula has the opposite sign,
        // so GL's counter-clockwise is Vulkan's clockwise.
        raster.frontFace = frontFace == GL.ccw ? VK_FRONT_FACE_CLOCKWISE : VK_FRONT_FACE_COUNTER_CLOCKWISE

        var multisample = VkPipelineMultisampleStateCreateInfo()
        multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
        multisample.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT

        func stencilState(_ face: GLStencilFace) -> VkStencilOpState {
            VkStencilOpState(
                failOp: stencilOp(face.fail), passOp: stencilOp(face.pass), depthFailOp: stencilOp(face.depthFail),
                compareOp: compareOp(face.function), compareMask: 0xFF, writeMask: 0xFF, reference: 0
            )
        }
        var depthStencil = VkPipelineDepthStencilStateCreateInfo()
        depthStencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depthStencil.depthTestEnable = key.depthTest ? VK_TRUE : VK_FALSE
        depthStencil.depthWriteEnable = key.depthWrite ? VK_TRUE : VK_FALSE
        depthStencil.depthCompareOp = compareOp(key.depthFunc)
        depthStencil.stencilTestEnable = key.stencilTest ? VK_TRUE : VK_FALSE
        depthStencil.front = stencilState(stencil.front)
        depthStencil.back = stencilState(stencil.back)
        depthStencil.maxDepthBounds = 1

        var attachment = VkPipelineColorBlendAttachmentState()
        attachment.blendEnable = blend ? VK_TRUE : VK_FALSE
        attachment.srcColorBlendFactor = blendFactor(blendSource.rgb)
        attachment.dstColorBlendFactor = blendFactor(blendDestination.rgb)
        attachment.colorBlendOp = blendOp(blendEquation.rgb)
        attachment.srcAlphaBlendFactor = blendFactor(blendSource.alpha)
        attachment.dstAlphaBlendFactor = blendFactor(blendDestination.alpha)
        attachment.alphaBlendOp = blendOp(blendEquation.alpha)
        attachment.colorWriteMask = VkColorComponentFlags(key.colorMask)

        let dynamicStates = [
            VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_BLEND_CONSTANTS,
            VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK, VK_DYNAMIC_STATE_STENCIL_WRITE_MASK, VK_DYNAMIC_STATE_STENCIL_REFERENCE,
        ]

        var pipeline: VkPipeline?
        let result = stages.withUnsafeBufferPointer { stagesPtr in
            bindings.withUnsafeBufferPointer { bindingsPtr in
                attributes.withUnsafeBufferPointer { attributesPtr in
                    dynamicStates.withUnsafeBufferPointer { dynamicPtr in
                        withUnsafePointer(to: &attachment) { attachmentPtr in
                            var vertexInput = VkPipelineVertexInputStateCreateInfo()
                            vertexInput.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
                            vertexInput.vertexBindingDescriptionCount = UInt32(bindingsPtr.count)
                            vertexInput.pVertexBindingDescriptions = bindingsPtr.baseAddress
                            vertexInput.vertexAttributeDescriptionCount = UInt32(attributesPtr.count)
                            vertexInput.pVertexAttributeDescriptions = attributesPtr.baseAddress
                            var colorBlend = VkPipelineColorBlendStateCreateInfo()
                            colorBlend.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
                            colorBlend.attachmentCount = 1
                            colorBlend.pAttachments = attachmentPtr
                            var dynamic = VkPipelineDynamicStateCreateInfo()
                            dynamic.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
                            dynamic.dynamicStateCount = UInt32(dynamicPtr.count)
                            dynamic.pDynamicStates = dynamicPtr.baseAddress
                            var info = VkGraphicsPipelineCreateInfo()
                            info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
                            info.stageCount = 2
                            info.pStages = stagesPtr.baseAddress
                            info.layout = layout
                            info.renderPass = target.renderPass
                            return withUnsafePointer(to: &vertexInput) { info.pVertexInputState = $0
                                return withUnsafePointer(to: &assembly) { info.pInputAssemblyState = $0
                                    return withUnsafePointer(to: &viewportState) { info.pViewportState = $0
                                        return withUnsafePointer(to: &raster) { info.pRasterizationState = $0
                                            return withUnsafePointer(to: &multisample) { info.pMultisampleState = $0
                                                return withUnsafePointer(to: &depthStencil) { info.pDepthStencilState = $0
                                                    return withUnsafePointer(to: &colorBlend) { info.pColorBlendState = $0
                                                        return withUnsafePointer(to: &dynamic) { info.pDynamicState = $0
                                                            return vkCreateGraphicsPipelines(device.device, nil, 1, &info, nil, &pipeline)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        guard result == VK_SUCCESS, let pipeline else { return nil }
        pipelines[key] = pipeline
        return pipeline
    }

    private func blendFactor(_ factor: GLenum) -> VkBlendFactor {
        switch factor {
        case GL.zero: VK_BLEND_FACTOR_ZERO
        case GL.one: VK_BLEND_FACTOR_ONE
        case GL.srcColor: VK_BLEND_FACTOR_SRC_COLOR
        case GL.oneMinusSrcColor: VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR
        case GL.dstColor: VK_BLEND_FACTOR_DST_COLOR
        case GL.oneMinusDstColor: VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR
        case GL.srcAlpha: VK_BLEND_FACTOR_SRC_ALPHA
        case GL.oneMinusSrcAlpha: VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
        case GL.dstAlpha: VK_BLEND_FACTOR_DST_ALPHA
        case GL.oneMinusDstAlpha: VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA
        case GL.srcAlphaSaturate: VK_BLEND_FACTOR_SRC_ALPHA_SATURATE
        // GL_CONSTANT_COLOR and friends — cgl.pxd misspells them, so they
        // have no `KIVY_NUI_GL_*` name.
        case 0x8001: VK_BLEND_FACTOR_CONSTANT_COLOR
        case 0x8002: VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR
        case 0x8003: VK_BLEND_FACTOR_CONSTANT_ALPHA
        case 0x8004: VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA
        default: VK_BLEND_FACTOR_ONE
        }
    }

    private func blendOp(_ equation: GLenum) -> VkBlendOp {
        switch equation {
        case GL.funcSubtract: VK_BLEND_OP_SUBTRACT
        case GL.funcReverseSubtract: VK_BLEND_OP_REVERSE_SUBTRACT
        default: VK_BLEND_OP_ADD
        }
    }

    /// GL's comparison enums run NEVER...ALWAYS in Vulkan's order.
    private func compareOp(_ function: GLenum) -> VkCompareOp {
        guard function >= GL.never, function <= GL.always else { return VK_COMPARE_OP_ALWAYS }
        return VkCompareOp(rawValue: function - GL.never)
    }

    private func stencilOp(_ op: GLenum) -> VkStencilOp {
        switch op {
        case GL.zero: VK_STENCIL_OP_ZERO
        case GL.replace: VK_STENCIL_OP_REPLACE
        case GL.incr: VK_STENCIL_OP_INCREMENT_AND_CLAMP
        case GL.decr: VK_STENCIL_OP_DECREMENT_AND_CLAMP
        case GL.invert: VK_STENCIL_OP_INVERT
        case GL.incrWrap: VK_STENCIL_OP_INCREMENT_AND_WRAP
        case GL.decrWrap: VK_STENCIL_OP_DECREMENT_AND_WRAP
        default: VK_STENCIL_OP_KEEP
        }
    }
}
