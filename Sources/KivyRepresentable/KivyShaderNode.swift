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
