//
//  GLObjects.swift
//  KivyRepresentable
//
//  What GL's names stand for: buffers kept on the CPU (uploaded per frame as
//  draws need them, which keeps GL's "a draw sees the data as it was when it
//  was issued" for free), textures and renderbuffers as Vulkan images,
//  framebuffers as attachment lists, shaders as source, programs as
//  translated SPIR-V plus the uniform values GL sets one at a time.
//

@preconcurrency import CVulkan

/// Never reused, unlike an object's address: a cache keyed by one can't
/// mistake a new object for a deleted one that stood at the same address.
nonisolated(unsafe) private var nextSerial = 0

func makeSerial() -> Int {
    nextSerial += 1
    return nextSerial
}

final class GLBuffer {
    var data: [UInt8] = []
    var usage: GLenum = GL.staticDraw
    /// New on every write, so a frame uploads a buffer again only when it
    /// has changed since its last upload.
    var version = makeSerial()
}

/// A Vulkan image and its memory and view, with the layout it is in.
final class GLImage {
    unowned let device: KivyGLDevice
    let image: VkImage
    let memory: VkDeviceMemory
    let view: VkImageView
    let format: VkFormat
    let width: Int
    let height: Int
    let levels: Int
    let aspect: VkImageAspectFlags
    let serial = makeSerial()
    var layout: VkImageLayout = VK_IMAGE_LAYOUT_UNDEFINED

    var isDepthStencil: Bool {
        aspect & VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue) == 0
    }

    init(device: KivyGLDevice, width: Int, height: Int, format: VkFormat, levels: Int = 1, usage: VkImageUsageFlags, aspect: VkImageAspectFlags) throws {
        self.device = device
        self.width = width
        self.height = height
        self.format = format
        self.levels = levels
        self.aspect = aspect

        var info = VkImageCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        info.imageType = VK_IMAGE_TYPE_2D
        info.format = format
        info.extent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        info.mipLevels = UInt32(levels)
        info.arrayLayers = 1
        info.samples = VK_SAMPLE_COUNT_1_BIT
        info.tiling = VK_IMAGE_TILING_OPTIMAL
        info.usage = usage
        info.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        var image: VkImage?
        guard vkCreateImage(device.device, &info, nil, &image) == VK_SUCCESS, let image else {
            throw KivyGLError.image
        }
        var requirements = VkMemoryRequirements()
        vkGetImageMemoryRequirements(device.device, image, &requirements)
        let memory: VkDeviceMemory
        do {
            memory = try device.allocate(requirements, properties: VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue))
        } catch {
            vkDestroyImage(device.device, image, nil)
            throw error
        }
        vkBindImageMemory(device.device, image, memory, 0)

        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = image
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = format
        viewInfo.subresourceRange = VkImageSubresourceRange(
            aspectMask: aspect, baseMipLevel: 0, levelCount: UInt32(levels), baseArrayLayer: 0, layerCount: 1
        )
        var view: VkImageView?
        guard vkCreateImageView(device.device, &viewInfo, nil, &view) == VK_SUCCESS, let view else {
            vkFreeMemory(device.device, memory, nil)
            vkDestroyImage(device.device, image, nil)
            throw KivyGLError.image
        }
        self.image = image
        self.memory = memory
        self.view = view
    }

    /// Only once no submitted work uses it — `KivyGL` retires images until
    /// the frame that last used them has finished.
    func destroy() {
        vkDestroyImageView(device.device, view, nil)
        vkDestroyImage(device.device, image, nil)
        vkFreeMemory(device.device, memory, nil)
    }
}

final class GLTexture {
    var image: GLImage?
    var minFilter = GL.nearestMipmapLinear
    var magFilter = GL.linear
    var wrapS = GL.`repeat`
    var wrapT = GL.`repeat`
    /// What glTexImage2D was asked for, for queries; the image is RGBA8.
    var internalFormat = GL.rgba
}

final class GLRenderbuffer {
    var image: GLImage?
    var internalFormat = GL.rgba4
}

final class GLFramebuffer {
    enum Attachment: Equatable {
        case texture(GLuint)
        case renderbuffer(GLuint)
    }

    var color: Attachment?
    var depth: Attachment?
    var stencil: Attachment?

    /// Built for the images below; remade when an attachment's image is not
    /// the one it was built for (a texture re-specified at a new size).
    var vkFramebuffer: VkFramebuffer?
    var builtFor: [Int] = []
}

final class GLShader {
    let stage: GLSLStage
    var source = ""
    var compiled = false
    var infoLog = ""
    var parsed: GLSLShaderSource?
    var deletePending = false

    init(stage: GLSLStage) {
        self.stage = stage
    }
}

final class GLProgram {
    struct Uniform {
        let variable: GLSLVariable
        /// The first of `variable.count` locations.
        let location: Int
        /// In the block; nil for a sampler.
        let offset: Int?
        let stride: Int
        /// The descriptor binding of a sampler.
        let binding: Int?
    }

    struct Attribute {
        let variable: GLSLVariable
        let location: Int
    }

    let serial = makeSerial()
    var shaders: [GLuint] = []
    var boundAttributes: [String: Int] = [:]
    var linked = false
    var infoLog = ""
    var deletePending = false

    // Set by a successful link.
    var attributes: [Attribute] = []
    var uniforms: [Uniform] = []
    /// Location → (uniform index, array element).
    var locations: [(uniform: Int, element: Int)] = []
    var blockSize = 0
    /// The block's bytes, as glUniform* left them.
    var blockData: [UInt8] = []
    /// Per sampler binding, the texture units glUniform1i gave its elements.
    var samplerUnits: [Int: [Int]] = [:]
    var vertexModule: VkShaderModule?
    var fragmentModule: VkShaderModule?
    var setLayout: VkDescriptorSetLayout?
    var pipelineLayout: VkPipelineLayout?
    /// Bumped by every link, so pipelines made for the previous one are not
    /// reused.
    var generation = 0
}

/// One generic vertex attribute: an array pointer, or the constant value a
/// disabled array reads.
struct GLVertexAttribute {
    var enabled = false
    var size: GLint = 4
    var type = GL.float
    var normalized = false
    var stride: GLsizei = 0
    var offset = 0
    var buffer: GLuint = 0
    var current: SIMD4<Float> = SIMD4(0, 0, 0, 1)
}
