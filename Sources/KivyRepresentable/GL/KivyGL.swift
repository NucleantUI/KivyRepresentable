//
//  KivyGL.swift
//  KivyRepresentable
//
//  Kivy's GLES2 on Vulkan — what ANGLE is to Kivy on Metal. Kivy calls the
//  `KivyNUIGL` table (kivy_nui_gl.h) exactly as it calls GL; each call lands
//  here (KivyGL+Table.swift), on the one context Kivy has.
//
//  GL is immediate and Vulkan is recorded, so calls are recorded into one
//  command buffer as they come and submitted at the end of Kivy's frame
//  (`present`), or earlier when GL has to hand something back (glReadPixels,
//  glFinish). Framebuffer 0 is an image of the context's own; `present`
//  copies it, flipped, into the shader node's image, which the engine
//  composites.
//

import Foundation
@preconcurrency import CVulkan

public final class KivyGL: @unchecked Sendable {

    /// The context the table's functions act on. Kivy is a singleton: one
    /// window, one GL context.
    nonisolated(unsafe) public static var current: KivyGL?

    public let device: KivyGLDevice

    // MARK: Objects

    var buffers: [GLuint: GLBuffer] = [:]
    var textures: [GLuint: GLTexture] = [:]
    var renderbuffers: [GLuint: GLRenderbuffer] = [:]
    var framebuffers: [GLuint: GLFramebuffer] = [:]
    var shaders: [GLuint: GLShader] = [:]
    var programs: [GLuint: GLProgram] = [:]
    var nextName: GLuint = 1

    // MARK: Bindings

    var arrayBuffer: GLuint = 0
    var elementArrayBuffer: GLuint = 0
    var activeTexture = 0
    var textureUnits = [GLuint](repeating: 0, count: KivyGL.maxTextureUnits)
    var boundFramebuffer: GLuint = 0
    var boundRenderbuffer: GLuint = 0
    var currentProgram: GLuint = 0
    var vertexAttributes = [GLVertexAttribute](repeating: GLVertexAttribute(), count: KivyGL.maxVertexAttributes)

    // MARK: Fixed-function state

    var viewport: (x: GLint, y: GLint, width: GLsizei, height: GLsizei) = (0, 0, 0, 0)
    var scissorBox: (x: GLint, y: GLint, width: GLsizei, height: GLsizei) = (0, 0, 0, 0)
    var scissorTest = false
    var blend = false
    var blendSource = (rgb: GL.one, alpha: GL.one)
    var blendDestination = (rgb: GL.zero, alpha: GL.zero)
    var blendEquation = (rgb: GL.funcAdd, alpha: GL.funcAdd)
    var blendColor: SIMD4<Float> = .zero
    var colorMask = (true, true, true, true)
    var clearColor: SIMD4<Float> = .zero
    var clearStencil: GLint = 0
    var depthTest = false
    var depthMask = true
    var depthFunc = GL.less
    var stencilTest = false
    var stencil = (front: GLStencilFace(), back: GLStencilFace())
    var cullFace = false
    var cullFaceMode = GL.back
    var frontFace = GL.ccw
    var dither = true
    var polygonOffsetFill = false
    var lineWidth: GLfloat = 1
    var unpackAlignment = 4
    var unpackRowLength = 0
    var packAlignment = 4

    var error = GL.noError

    // MARK: Framebuffer 0

    /// What Kivy draws into when framebuffer 0 is bound.
    var defaultColor: GLImage?
    var defaultDepthStencil: GLImage?
    var defaultVkFramebuffer: VkFramebuffer?

    /// Where `present` copies framebuffer 0: the shader node's image.
    var presentTarget: (image: VkImage, width: Int, height: Int, layout: VkImageLayout)?

    // MARK: Recording (GLFrame.swift)

    var frame: GLFrame!
    var samplers: [String: VkSampler] = [:]
    var blankImage: GLImage?
    var pipelines: [GLPipelineKey: VkPipeline] = [:]

    static let maxTextureUnits = 16
    static let maxVertexAttributes = 16
    static let maxTextureSize = 8192

    /// A context with framebuffer 0 `width` x `height` pixels.
    public init(device: KivyGLDevice, width: Int, height: Int) throws {
        self.device = device
        self.frame = try GLFrame(device: device)
        try resizeDefaultFramebuffer(width: width, height: height)
        viewport = (0, 0, GLsizei(width), GLsizei(height))
        scissorBox = viewport
    }

    deinit {
        frame.finish()
        for texture in textures.values { texture.image?.destroy() }
        for renderbuffer in renderbuffers.values { renderbuffer.image?.destroy() }
        for framebuffer in framebuffers.values {
            if let vk = framebuffer.vkFramebuffer { vkDestroyFramebuffer(device.device, vk, nil) }
        }
        for program in programs.values { destroyPipelineObjects(of: program) }
        for pipeline in pipelines.values { vkDestroyPipeline(device.device, pipeline, nil) }
        for sampler in samplers.values { vkDestroySampler(device.device, sampler, nil) }
        blankImage?.destroy()
        if let defaultVkFramebuffer { vkDestroyFramebuffer(device.device, defaultVkFramebuffer, nil) }
        defaultColor?.destroy()
        defaultDepthStencil?.destroy()
        frame.destroy()
    }

    /// Framebuffer 0 at a new size — the window's, in pixels. Its contents
    /// are lost, as a GL window's are on a resize.
    public func resizeDefaultFramebuffer(width: Int, height: Int) throws {
        let width = max(1, width)
        let height = max(1, height)
        if let defaultColor, defaultColor.width == width, defaultColor.height == height { return }
        frame.endPass()
        if let color = defaultColor { frame.retire { color.destroy() } }
        if let depthStencil = defaultDepthStencil { frame.retire { depthStencil.destroy() } }
        if let vk = defaultVkFramebuffer {
            let device = device.device
            frame.retire { vkDestroyFramebuffer(device, vk, nil) }
        }
        defaultVkFramebuffer = nil
        defaultColor = try GLImage(
            device: device, width: width, height: height, format: Self.colorFormat,
            usage: Self.colorUsage,
            aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        )
        defaultDepthStencil = try makeDepthStencilImage(width: width, height: height)
    }

    /// Every color image: sampled, rendered to, copied both ways.
    static let colorFormat = VK_FORMAT_R8G8B8A8_UNORM
    static let colorUsage = VkImageUsageFlags(
        VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue
            | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue
    )

    func makeDepthStencilImage(width: Int, height: Int) throws -> GLImage {
        try GLImage(
            device: device, width: width, height: height, format: device.depthStencilFormat,
            usage: VkImageUsageFlags(VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue),
            aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_DEPTH_BIT.rawValue | VK_IMAGE_ASPECT_STENCIL_BIT.rawValue)
        )
    }

    func setError(_ code: GLenum) {
        if error == GL.noError { error = code }
    }

    func getError() -> GLenum {
        defer { error = GL.noError }
        return error
    }

    // MARK: - Names

    func generate(_ count: GLsizei, _ out: UnsafeMutablePointer<GLuint>?, make: (GLuint) -> Void) {
        guard count >= 0 else { return setError(GL.invalidValue) }
        guard let out else { return }
        for index in 0..<Int(count) {
            let name = nextName
            nextName += 1
            make(name)
            out[index] = name
        }
    }

    func genBuffers(_ n: GLsizei, _ out: UnsafeMutablePointer<GLuint>?) {
        generate(n, out) { buffers[$0] = GLBuffer() }
    }

    func genTextures(_ n: GLsizei, _ out: UnsafeMutablePointer<GLuint>?) {
        generate(n, out) { textures[$0] = GLTexture() }
    }

    func genFramebuffers(_ n: GLsizei, _ out: UnsafeMutablePointer<GLuint>?) {
        generate(n, out) { framebuffers[$0] = GLFramebuffer() }
    }

    func genRenderbuffers(_ n: GLsizei, _ out: UnsafeMutablePointer<GLuint>?) {
        generate(n, out) { renderbuffers[$0] = GLRenderbuffer() }
    }

    func deleteBuffers(_ n: GLsizei, _ names: UnsafePointer<GLuint>?) {
        guard let names, n > 0 else { return }
        for name in UnsafeBufferPointer(start: names, count: Int(n)) where name != 0 {
            buffers[name] = nil
            if arrayBuffer == name { arrayBuffer = 0 }
            if elementArrayBuffer == name { elementArrayBuffer = 0 }
            for index in vertexAttributes.indices where vertexAttributes[index].buffer == name {
                vertexAttributes[index].buffer = 0
            }
        }
    }

    func deleteTextures(_ n: GLsizei, _ names: UnsafePointer<GLuint>?) {
        guard let names, n > 0 else { return }
        for name in UnsafeBufferPointer(start: names, count: Int(n)) where name != 0 {
            if let image = textures.removeValue(forKey: name)?.image {
                frame.retire { image.destroy() }
            }
            for unit in textureUnits.indices where textureUnits[unit] == name {
                textureUnits[unit] = 0
            }
        }
    }

    func deleteRenderbuffers(_ n: GLsizei, _ names: UnsafePointer<GLuint>?) {
        guard let names, n > 0 else { return }
        for name in UnsafeBufferPointer(start: names, count: Int(n)) where name != 0 {
            if let image = renderbuffers.removeValue(forKey: name)?.image {
                frame.retire { image.destroy() }
            }
            if boundRenderbuffer == name { boundRenderbuffer = 0 }
        }
    }

    func deleteFramebuffers(_ n: GLsizei, _ names: UnsafePointer<GLuint>?) {
        guard let names, n > 0 else { return }
        for name in UnsafeBufferPointer(start: names, count: Int(n)) where name != 0 {
            if let vk = framebuffers.removeValue(forKey: name)?.vkFramebuffer {
                let device = device.device
                frame.retire { vkDestroyFramebuffer(device, vk, nil) }
            }
            if boundFramebuffer == name { bindFramebuffer(GL.framebuffer, 0) }
        }
    }

    func isObject(_ name: GLuint, in table: [GLuint: some AnyObject]) -> GLboolean {
        table[name] != nil ? 1 : 0
    }

    // MARK: - Binding

    func bindBuffer(_ target: GLenum, _ name: GLuint) {
        if name != 0 && buffers[name] == nil { buffers[name] = GLBuffer() }
        switch target {
        case GL.arrayBuffer: arrayBuffer = name
        case GL.elementArrayBuffer: elementArrayBuffer = name
        default: setError(GL.invalidEnum)
        }
    }

    func bindTexture(_ target: GLenum, _ name: GLuint) {
        guard target == GL.texture2D else { return setError(GL.invalidEnum) }
        if name != 0 && textures[name] == nil { textures[name] = GLTexture() }
        textureUnits[activeTexture] = name
    }

    func setActiveTexture(_ unit: GLenum) {
        let index = Int(unit) - Int(GL.texture0)
        guard index >= 0 && index < Self.maxTextureUnits else { return setError(GL.invalidEnum) }
        activeTexture = index
    }

    func bindFramebuffer(_ target: GLenum, _ name: GLuint) {
        guard target == GL.framebuffer else { return setError(GL.invalidEnum) }
        if name != 0 && framebuffers[name] == nil { framebuffers[name] = GLFramebuffer() }
        boundFramebuffer = name
    }

    func bindRenderbuffer(_ target: GLenum, _ name: GLuint) {
        guard target == GL.renderbuffer else { return setError(GL.invalidEnum) }
        if name != 0 && renderbuffers[name] == nil { renderbuffers[name] = GLRenderbuffer() }
        boundRenderbuffer = name
    }

    var boundTexture: GLTexture? {
        textures[textureUnits[activeTexture]]
    }

    // MARK: - Buffers

    func bufferData(_ target: GLenum, _ size: Int, _ data: UnsafeRawPointer?, _ usage: GLenum) {
        guard let buffer = buffer(for: target) else { return }
        guard size >= 0 else { return setError(GL.invalidValue) }
        if let data {
            buffer.data = Array(UnsafeRawBufferPointer(start: data, count: size))
        } else {
            buffer.data = [UInt8](repeating: 0, count: size)
        }
        buffer.usage = usage
        buffer.version = makeSerial()
    }

    func bufferSubData(_ target: GLenum, _ offset: Int, _ size: Int, _ data: UnsafeRawPointer?) {
        guard let buffer = buffer(for: target) else { return }
        guard offset >= 0, size >= 0, offset + size <= buffer.data.count else { return setError(GL.invalidValue) }
        guard let data, size > 0 else { return }
        buffer.data.withUnsafeMutableBytes { bytes in
            bytes.baseAddress!.advanced(by: offset).copyMemory(from: data, byteCount: size)
        }
        buffer.version = makeSerial()
    }

    private func buffer(for target: GLenum) -> GLBuffer? {
        let name: GLuint
        switch target {
        case GL.arrayBuffer: name = arrayBuffer
        case GL.elementArrayBuffer: name = elementArrayBuffer
        default:
            setError(GL.invalidEnum)
            return nil
        }
        guard let buffer = buffers[name] else {
            setError(GL.invalidOperation)
            return nil
        }
        return buffer
    }

    // MARK: - Vertex attributes

    func vertexAttribPointer(_ index: GLuint, _ size: GLint, _ type: GLenum, _ normalized: GLboolean, _ stride: GLsizei, _ pointer: UnsafeRawPointer?) {
        guard Int(index) < Self.maxVertexAttributes, (1...4).contains(size), stride >= 0 else { return setError(GL.invalidValue) }
        var attribute = vertexAttributes[Int(index)]
        attribute.size = size
        attribute.type = type
        attribute.normalized = normalized != 0
        attribute.stride = stride
        attribute.offset = Int(bitPattern: pointer)
        attribute.buffer = arrayBuffer
        vertexAttributes[Int(index)] = attribute
    }

    func setVertexAttribArray(_ index: GLuint, enabled: Bool) {
        guard Int(index) < Self.maxVertexAttributes else { return setError(GL.invalidValue) }
        vertexAttributes[Int(index)].enabled = enabled
    }

    func vertexAttrib(_ index: GLuint, _ value: SIMD4<Float>) {
        guard Int(index) < Self.maxVertexAttributes else { return setError(GL.invalidValue) }
        vertexAttributes[Int(index)].current = value
    }

    // MARK: - Capabilities

    func setCapability(_ cap: GLenum, _ on: Bool) {
        switch cap {
        case GL.blend: blend = on
        case GL.scissorTest: scissorTest = on
        case GL.depthTest: depthTest = on
        case GL.stencilTest: stencilTest = on
        case GL.cullFace: cullFace = on
        case GL.dither: dither = on
        case GL.polygonOffsetFill: polygonOffsetFill = on
        case GL.sampleAlphaToCoverage, GL.sampleCoverage: break
        default: setError(GL.invalidEnum)
        }
    }

    func isEnabled(_ cap: GLenum) -> GLboolean {
        let on: Bool
        switch cap {
        case GL.blend: on = blend
        case GL.scissorTest: on = scissorTest
        case GL.depthTest: on = depthTest
        case GL.stencilTest: on = stencilTest
        case GL.cullFace: on = cullFace
        case GL.dither: on = dither
        case GL.polygonOffsetFill: on = polygonOffsetFill
        default:
            setError(GL.invalidEnum)
            on = false
        }
        return on ? 1 : 0
    }

    func pixelStore(_ pname: GLenum, _ value: GLint) {
        switch pname {
        case GL.unpackAlignment where [1, 2, 4, 8].contains(value): unpackAlignment = Int(value)
        case GL.packAlignment where [1, 2, 4, 8].contains(value): packAlignment = Int(value)
        case GL.unpackRowLength where value >= 0: unpackRowLength = Int(value)
        case GL.unpackAlignment, GL.packAlignment, GL.unpackRowLength: setError(GL.invalidValue)
        default: setError(GL.invalidEnum)
        }
    }

    func setStencilFunc(_ face: GLenum, _ function: GLenum, _ reference: GLint, _ mask: GLuint) {
        if face == GL.front || face == GL.frontAndBack {
            stencil.front.function = function
            stencil.front.reference = reference
            stencil.front.valueMask = mask
        }
        if face == GL.back || face == GL.frontAndBack {
            stencil.back.function = function
            stencil.back.reference = reference
            stencil.back.valueMask = mask
        }
    }

    func setStencilOp(_ face: GLenum, _ fail: GLenum, _ depthFail: GLenum, _ pass: GLenum) {
        if face == GL.front || face == GL.frontAndBack {
            stencil.front.fail = fail
            stencil.front.depthFail = depthFail
            stencil.front.pass = pass
        }
        if face == GL.back || face == GL.frontAndBack {
            stencil.back.fail = fail
            stencil.back.depthFail = depthFail
            stencil.back.pass = pass
        }
    }

    func setStencilMask(_ face: GLenum, _ mask: GLuint) {
        if face == GL.front || face == GL.frontAndBack { stencil.front.writeMask = mask }
        if face == GL.back || face == GL.frontAndBack { stencil.back.writeMask = mask }
    }

    // MARK: - Queries

    func getIntegers(_ pname: GLenum) -> [GLint]? {
        func bool(_ value: Bool) -> GLint { value ? 1 : 0 }
        switch pname {
        case GL.viewport: return [viewport.x, viewport.y, viewport.width, viewport.height]
        case GL.scissorBox: return [scissorBox.x, scissorBox.y, scissorBox.width, scissorBox.height]
        case GL.framebufferBinding: return [GLint(boundFramebuffer)]
        case GL.renderbufferBinding: return [GLint(boundRenderbuffer)]
        case GL.currentProgram: return [GLint(currentProgram)]
        case GL.arrayBufferBinding: return [GLint(arrayBuffer)]
        case GL.elementArrayBufferBinding: return [GLint(elementArrayBuffer)]
        case GL.textureBinding2D: return [GLint(textureUnits[activeTexture])]
        case GL.activeTexture: return [GLint(GL.texture0) + GLint(activeTexture)]
        case GL.maxTextureSize, GL.maxRenderbufferSize: return [GLint(Self.maxTextureSize)]
        case GL.maxViewportDims: return [GLint(Self.maxTextureSize), GLint(Self.maxTextureSize)]
        case GL.maxTextureImageUnits, GL.maxCombinedTextureImageUnits: return [GLint(Self.maxTextureUnits)]
        case GL.maxVertexTextureImageUnits: return [GLint(Self.maxTextureUnits)]
        case GL.maxVertexAttribs: return [GLint(Self.maxVertexAttributes)]
        case GL.maxVertexUniformVectors, GL.maxFragmentUniformVectors: return [256]
        case GL.maxVaryingVectors: return [15]
        case GL.maxCubeMapTextureSize: return [GLint(Self.maxTextureSize)]
        case GL.redBits, GL.greenBits, GL.blueBits, GL.alphaBits, GL.stencilBits: return [8]
        case GL.depthBits: return [24]
        case GL.subpixelBits: return [4]
        case GL.samples, GL.sampleBuffers: return [0]
        case GL.unpackAlignment: return [GLint(unpackAlignment)]
        case GL.packAlignment: return [GLint(packAlignment)]
        case GL.numCompressedTextureFormats, GL.numShaderBinaryFormats: return [0]
        case GL.blend: return [bool(blend)]
        case GL.scissorTest: return [bool(scissorTest)]
        case GL.depthTest: return [bool(depthTest)]
        case GL.stencilTest: return [bool(stencilTest)]
        case GL.cullFace: return [bool(cullFace)]
        case GL.blendSrcRgb: return [GLint(blendSource.rgb)]
        case GL.blendSrcAlpha: return [GLint(blendSource.alpha)]
        case GL.blendDstRgb: return [GLint(blendDestination.rgb)]
        case GL.blendDstAlpha: return [GLint(blendDestination.alpha)]
        case GL.blendEquationRgb: return [GLint(blendEquation.rgb)]
        case GL.blendEquationAlpha: return [GLint(blendEquation.alpha)]
        case GL.depthFunc: return [GLint(depthFunc)]
        case GL.depthWritemask: return [bool(depthMask)]
        case GL.colorWritemask: return [bool(colorMask.0), bool(colorMask.1), bool(colorMask.2), bool(colorMask.3)]
        case GL.stencilFunc: return [GLint(stencil.front.function)]
        case GL.stencilRef: return [stencil.front.reference]
        case GL.stencilValueMask: return [GLint(bitPattern: stencil.front.valueMask)]
        case GL.stencilWritemask: return [GLint(bitPattern: stencil.front.writeMask)]
        case GL.stencilFail: return [GLint(stencil.front.fail)]
        case GL.stencilPassDepthFail: return [GLint(stencil.front.depthFail)]
        case GL.stencilPassDepthPass: return [GLint(stencil.front.pass)]
        case GL.stencilBackFunc: return [GLint(stencil.back.function)]
        case GL.stencilBackRef: return [stencil.back.reference]
        case GL.stencilBackValueMask: return [GLint(bitPattern: stencil.back.valueMask)]
        case GL.stencilBackWritemask: return [GLint(bitPattern: stencil.back.writeMask)]
        case GL.stencilBackFail: return [GLint(stencil.back.fail)]
        case GL.stencilBackPassDepthFail: return [GLint(stencil.back.depthFail)]
        case GL.stencilBackPassDepthPass: return [GLint(stencil.back.pass)]
        case GL.stencilClearValue: return [clearStencil]
        case GL.cullFaceMode: return [GLint(cullFaceMode)]
        case GL.frontFace: return [GLint(frontFace)]
        case GL.implementationColorReadFormat: return [GLint(GL.rgba)]
        case GL.implementationColorReadType: return [GLint(GL.unsignedByte)]
        case GL.generateMipmapHint: return [GLint(GL.dontCare)]
        case GL.shaderCompiler: return [1]
        default: return nil
        }
    }

    func getFloats(_ pname: GLenum) -> [GLfloat]? {
        switch pname {
        case GL.colorClearValue: return [clearColor.x, clearColor.y, clearColor.z, clearColor.w]
        case GL.blendColor: return [blendColor.x, blendColor.y, blendColor.z, blendColor.w]
        case GL.lineWidth: return [lineWidth]
        case GL.aliasedLineWidthRange: return [1, 1]
        case GL.aliasedPointSizeRange: return [1, 64]
        case GL.depthRange: return [0, 1]
        case GL.depthClearValue: return [1]
        default: return getIntegers(pname)?.map { GLfloat($0) }
        }
    }

    // MARK: - Strings

    /// Kept for the process: glGetString's pointers must stay valid.
    nonisolated(unsafe) private static var strings: [GLenum: UnsafeMutablePointer<CChar>] = [:]

    func getString(_ name: GLenum) -> UnsafePointer<GLubyte>? {
        let value: String
        switch name {
        case GL.vendor: value = "NucleantUI"
        case GL.renderer: value = "KivyRepresentable (Vulkan)"
        case GL.version: value = "OpenGL ES 2.0 KivyRepresentable"
        case GL.shadingLanguageVersion: value = "OpenGL ES GLSL ES 1.00"
        case GL.extensions:
            value = [
                "GL_EXT_bgra", "GL_EXT_texture_format_BGRA8888", "GL_OES_texture_npot",
                "GL_ARB_texture_non_power_of_two", "GL_OES_element_index_uint",
                "GL_OES_packed_depth_stencil", "GL_OES_rgb8_rgba8", "GL_EXT_unpack_subimage",
            ].joined(separator: " ")
        default:
            setError(GL.invalidEnum)
            return nil
        }
        if Self.strings[name] == nil { Self.strings[name] = strdup(value) }
        return UnsafeRawPointer(Self.strings[name]!).assumingMemoryBound(to: GLubyte.self)
    }
}

struct GLStencilFace {
    var function = GL.always
    var reference: GLint = 0
    var valueMask: GLuint = 0xFFFF_FFFF
    var writeMask: GLuint = 0xFFFF_FFFF
    var fail = GL.keep
    var depthFail = GL.keep
    var pass = GL.keep
}
