//
//  KivyShaderNode.swift
//  KivyRepresentable
//
//  Kivy's one shared image: Kivy draws its whole window into it every frame
//  through the GL table, and the engine composites it like any other node.
//

import Observation
@preconcurrency import CVulkan
import NucleantVulkan

@Observable
public final class KivyShaderNode<ContainerNode: RenderContainerNode>: VulkanRenderNode, @unchecked Sendable {

    public typealias Engine = VulkanRenderEngine<ContainerNode>

    @ObservationIgnored public var width:  UInt32
    @ObservationIgnored public var height: UInt32

    @ObservationIgnored public var image:     VkImage
    @ObservationIgnored public var imageView: VkImageView
    @ObservationIgnored public var memory:    VkDeviceMemory?

    public var dirty: Bool = true

    public var computePipeline:      VkPipeline?
    public var computeLayout:        VkPipelineLayout?
    public var computeDescriptorSet: VkDescriptorSet?
    public let storageCapable = false

    /// Whether Kivy has drawn a frame into `image` yet. Until it has, the
    /// image stays out of the composite.
    @ObservationIgnored public var hasContent = false

    public init(
        width:     UInt32,
        height:    UInt32,
        image:     VkImage,
        imageView: VkImageView,
        memory:    VkDeviceMemory? = nil
    ) {
        self.width     = width
        self.height    = height
        self.image     = image
        self.imageView = imageView
        self.memory    = memory
    }

    public func update(_ engine: Engine, slot: ContainerNode, cmd: VkCommandBuffer) {
        guard hasContent else { return }
        engine.readable.insert(slot.id)
    }

    public func destroyResources(_ engine: Engine) {
        vkDeviceWaitIdle(engine.device)
        vkDestroyImageView(engine.device, imageView, nil)
        vkDestroyImage(engine.device, image, nil)
        if let memory {
            vkFreeMemory(engine.device, memory, nil)
        }
    }
}

extension KivyShaderNode {
    /// A node with an image of its own, `width` x `height` pixels: what
    /// Kivy's frames are copied into (`KivyGL.present`).
    public static func make(device: KivyGLDevice, width: Int, height: Int) throws -> KivyShaderNode {
        let image = try Self.makeImage(device: device, width: width, height: height)
        return KivyShaderNode(
            width: UInt32(image.width), height: UInt32(image.height),
            image: image.image, imageView: image.view, memory: image.memory
        )
    }

    /// Swap in an image at the new size. The old one is handed back to be
    /// freed once no frame in flight samples it.
    public func resize(device: KivyGLDevice, width: Int, height: Int) throws -> (image: VkImage, view: VkImageView, memory: VkDeviceMemory?) {
        let replacement = try Self.makeImage(device: device, width: width, height: height)
        let old = (image, imageView, memory)
        image = replacement.image
        imageView = replacement.view
        memory = replacement.memory
        self.width = UInt32(width)
        self.height = UInt32(height)
        hasContent = false
        return old
    }

    private static func makeImage(device: KivyGLDevice, width: Int, height: Int) throws -> GLImage {
        try GLImage(
            device: device, width: max(1, width), height: max(1, height), format: KivyGL.colorFormat,
            usage: VkImageUsageFlags(VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue),
            aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        )
    }
}
