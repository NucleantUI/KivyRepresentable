import Foundation
import Testing
import CKivyNUI
import CVulkan
import NucleantSkia
@testable import KivyRepresentable

/// Kivy's own shaders, as `shader.pyx` hands them over: header.vs/.fs
/// pasted in for `$HEADER$` (kivy/data/glsl).
private let kivyVertex = """
#ifdef GL_ES
    precision highp float;
#endif

/* Outputs to the fragment shader */
varying vec4 frag_color;
varying vec2 tex_coord0;

/* vertex attributes */
attribute vec2     vPosition;
attribute vec2     vTexCoords0;

/* uniform variables */
uniform mat4       modelview_mat;
uniform mat4       projection_mat;
uniform vec4       color;
uniform float      opacity;
void main (void) {
  frag_color = color * vec4(1.0, 1.0, 1.0, opacity);
  tex_coord0 = vTexCoords0;
  gl_Position = projection_mat * modelview_mat * vec4(vPosition.xy, 0.0, 1.0);
}
"""

private let kivyFragment = """
#ifdef GL_ES
    precision highp float;
#endif

/* Outputs from the vertex shader */
varying vec4 frag_color;
varying vec2 tex_coord0;

/* uniform texture samplers */
uniform sampler2D texture0;

uniform mat4 frag_modelview_mat;
void main (void){
    gl_FragColor = frag_color * texture2D(texture0, tex_coord0);
}
"""

/// Kivy's side of the table: every call goes through the C function
/// pointers, the way Kivy's cgl makes it.
@MainActor
private final class KivyLikeClient {
    let gl: KivyGL
    let t: KivyNUIGL
    let width: Int
    let height: Int

    init(width: Int = 64, height: Int = 64) throws {
        gl = try KivyGL(device: KivyGLTests.device(), width: width, height: height)
        KivyGL.current = gl
        t = KivyGL.table.pointee
        self.width = width
        self.height = height
        t.glViewport!(0, 0, GLsizei(width), GLsizei(height))
    }

    func compile(_ type: GLenum, _ source: String) -> GLuint {
        let shader = t.glCreateShader!(type)
        source.withCString { pointer in
            var string: UnsafePointer<CChar>? = pointer
            t.glShaderSource!(shader, 1, &string, nil)
        }
        t.glCompileShader!(shader)
        var status: GLint = 0
        t.glGetShaderiv!(shader, GL.compileStatus, &status)
        #expect(status == 1, "\(log(shader: shader))")
        return shader
    }

    func log(shader: GLuint) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        var length: GLsizei = 0
        t.glGetShaderInfoLog!(shader, 4096, &length, &buffer)
        return String(cString: buffer)
    }

    /// Kivy's default program, linked and in use.
    func kivyProgram(vertex: String = kivyVertex, fragment: String = kivyFragment) -> GLuint {
        let program = t.glCreateProgram!()
        t.glAttachShader!(program, compile(GL.vertexShader, vertex))
        t.glAttachShader!(program, compile(GL.fragmentShader, fragment))
        t.glLinkProgram!(program)
        var status: GLint = 0
        t.glGetProgramiv!(program, GL.linkStatus, &status)
        var buffer = [CChar](repeating: 0, count: 4096)
        t.glGetProgramInfoLog!(program, 4096, nil, &buffer)
        #expect(status == 1, "\(String(cString: buffer))")
        t.glUseProgram!(program)
        return program
    }

    func uniform(_ program: GLuint, _ name: String) -> GLint {
        t.glGetUniformLocation!(program, name)
    }

    func attribute(_ program: GLuint, _ name: String) -> GLuint {
        GLuint(t.glGetAttribLocation!(program, name))
    }

    /// Kivy's 2D setup: pixel coordinates, origin bottom-left.
    func setupProjection(_ program: GLuint, color: SIMD4<Float> = .one, width: Int? = nil, height: Int? = nil) {
        let w = Float(width ?? self.width), h = Float(height ?? self.height)
        let projection: [Float] = [2 / w, 0, 0, 0, 0, 2 / h, 0, 0, 0, 0, -1, 0, -1, -1, 0, 1]
        let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        t.glUniformMatrix4fv!(uniform(program, "projection_mat"), 1, 0, projection)
        t.glUniformMatrix4fv!(uniform(program, "modelview_mat"), 1, 0, identity)
        t.glUniform4f!(uniform(program, "color"), color.x, color.y, color.z, color.w)
        t.glUniform1f!(uniform(program, "opacity"), 1)
        t.glUniform1i!(uniform(program, "texture0"), 0)
    }

    /// A texture of `pixels` (RGBA rows, first row first) bound to unit 0.
    @discardableResult
    func texture(width: Int, height: Int, pixels: [UInt8], filter: GLenum = GL.nearest) -> GLuint {
        var name: GLuint = 0
        t.glGenTextures!(1, &name)
        t.glActiveTexture!(GL.texture0)
        t.glBindTexture!(GL.texture2D, name)
        t.glTexParameteri!(GL.texture2D, GL.textureMinFilter, GLint(filter))
        t.glTexParameteri!(GL.texture2D, GL.textureMagFilter, GLint(filter))
        t.glTexParameteri!(GL.texture2D, GL.textureWrapS, GLint(GL.clampToEdge))
        t.glTexParameteri!(GL.texture2D, GL.textureWrapT, GLint(GL.clampToEdge))
        t.glTexImage2D!(GL.texture2D, 0, GLint(GL.rgba), GLsizei(width), GLsizei(height), 0, GL.rgba, GL.unsignedByte, pixels)
        return name
    }

    /// Kivy's Rectangle: four (x, y, u, v) vertices in one VBO, drawn as
    /// GL_TRIANGLES with indices 0 1 2 2 3 0, unsigned short.
    func rectangle(_ program: GLuint, x: Float, y: Float, width: Float, height: Float, mode: GLenum = GL.triangles, indices: [UInt16] = [0, 1, 2, 2, 3, 0]) {
        let vertices: [Float] = [
            x, y, 0, 0,
            x + width, y, 1, 0,
            x + width, y + height, 1, 1,
            x, y + height, 0, 1,
        ]
        var buffers: [GLuint] = [0, 0]
        t.glGenBuffers!(2, &buffers)
        t.glBindBuffer!(GL.arrayBuffer, buffers[0])
        t.glBufferData!(GL.arrayBuffer, vertices.count * 4, vertices, GL.streamDraw)
        t.glBindBuffer!(GL.elementArrayBuffer, buffers[1])
        t.glBufferData!(GL.elementArrayBuffer, indices.count * 2, indices, GL.streamDraw)
        let position = attribute(program, "vPosition")
        let texCoords = attribute(program, "vTexCoords0")
        t.glEnableVertexAttribArray!(position)
        t.glEnableVertexAttribArray!(texCoords)
        t.glVertexAttribPointer!(position, 2, GL.float, 0, 16, nil)
        t.glVertexAttribPointer!(texCoords, 2, GL.float, 0, 16, UnsafeRawPointer(bitPattern: 8))
        t.glDrawElements!(mode, GLsizei(indices.count), GL.unsignedShort, nil)
        t.glDeleteBuffers!(2, buffers)
    }

    /// glReadPixels of the whole framebuffer, RGBA, row 0 the bottom.
    func read() -> [SIMD4<UInt8>] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        t.glReadPixels!(0, 0, GLsizei(width), GLsizei(height), GL.rgba, GL.unsignedByte, &pixels)
        return stride(from: 0, to: pixels.count, by: 4).map {
            SIMD4(pixels[$0], pixels[$0 + 1], pixels[$0 + 2], pixels[$0 + 3])
        }
    }

    func pixel(_ pixels: [SIMD4<UInt8>], x: Int, y: Int) -> SIMD4<UInt8> {
        pixels[y * width + x]
    }

    func clear(_ color: SIMD4<Float>) {
        t.glClearColor!(color.x, color.y, color.z, color.w)
        t.glClear!(GL.colorBufferBit | GL.stencilBufferBit)
    }

    var error: GLenum { t.glGetError!() }
}

private let red = SIMD4<UInt8>(255, 0, 0, 255)
private let green = SIMD4<UInt8>(0, 255, 0, 255)
private let blue = SIMD4<UInt8>(0, 0, 255, 255)
private let white = SIMD4<UInt8>(255, 255, 255, 255)
private let black = SIMD4<UInt8>(0, 0, 0, 255)

@MainActor
@Suite(.serialized)
struct KivyGLTests {

    nonisolated(unsafe) static var shared: KivyGLDevice?

    static func device() throws -> KivyGLDevice {
        if let shared { return shared }
        let device = try KivyGLDevice.headless()
        shared = device
        return device
    }

    @Test func clearFillsFramebufferZero() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(1, 0, 0, 1))
        let pixels = kivy.read()
        #expect(pixels.allSatisfy { $0 == red })
        #expect(kivy.error == GL.noError)
    }

    @Test func scissoredClearCountsRowsFromTheBottom() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        kivy.t.glEnable!(GL.scissorTest)
        kivy.t.glScissor!(0, 0, 64, 16)
        kivy.t.glClearColor!(0, 1, 0, 1)
        kivy.t.glClear!(GL.colorBufferBit)
        kivy.t.glDisable!(GL.scissorTest)
        let pixels = kivy.read()
        // GL's scissor y is from the bottom, and so is glReadPixels' row 0.
        #expect(kivy.pixel(pixels, x: 10, y: 5) == green)
        #expect(kivy.pixel(pixels, x: 10, y: 40) == black)
    }

    @Test func kivyDefaultShaderLinksWithKivysNames() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        #expect(kivy.t.glGetAttribLocation!(program, "vPosition") >= 0)
        #expect(kivy.t.glGetAttribLocation!(program, "vTexCoords0") >= 0)
        for name in ["modelview_mat", "projection_mat", "color", "opacity", "texture0", "frag_modelview_mat"] {
            #expect(kivy.uniform(program, name) >= 0, "\(name)")
        }
        #expect(kivy.uniform(program, "missing") == -1)
        #expect(kivy.error == GL.noError)
    }

    @Test func rectangleDrawsWhereKivyPutsIt() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program, color: SIMD4(0, 0, 1, 1))
        kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])
        // Bottom-left quarter, in Kivy's coordinates.
        kivy.rectangle(program, x: 0, y: 0, width: 32, height: 32)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 10, y: 10) == blue)
        #expect(kivy.pixel(pixels, x: 50, y: 50) == black)
        #expect(kivy.pixel(pixels, x: 10, y: 50) == black)
    }

    @Test func textureRowZeroIsSampledAtTheBottom() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        // Row 0 (first uploaded) red/green, row 1 blue/white.
        kivy.texture(width: 2, height: 2, pixels: [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ])
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.pixel(pixels, x: 10, y: 10) == red)
        #expect(kivy.pixel(pixels, x: 50, y: 10) == green)
        #expect(kivy.pixel(pixels, x: 10, y: 50) == blue)
        #expect(kivy.pixel(pixels, x: 50, y: 50) == white)
    }

    /// A texture shrunk with no mipmaps samples level 0 with MIN_FILTER:
    /// nearest picks texels, even when MAG_FILTER is linear.
    @Test func minificationWithoutMipmapsUsesTheMinFilter() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        // A 1-texel checker, 64x64, drawn at 8x8: every pixel lands between
        // texels, where linear would mix black and white into grey.
        let checker: [UInt8] = (0..<64).flatMap { y in
            (0..<64).flatMap { x -> [UInt8] in (x + y) % 2 == 1 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        }
        kivy.texture(width: 64, height: 64, pixels: checker, filter: GL.nearest)
        kivy.t.glTexParameteri!(GL.texture2D, GL.textureMagFilter, GLint(GL.linear))
        kivy.rectangle(program, x: 0, y: 0, width: 8, height: 8)
        let pixels = kivy.read()
        for y in 0..<8 {
            for x in 0..<8 {
                let p = kivy.pixel(pixels, x: x, y: y)
                #expect(p == black || p == white, "(\(x), \(y)) is \(p)")
            }
        }
        #expect(kivy.error == GL.noError)
    }

    @Test func rgbLuminanceAndBGRAUploadsBecomeRGBA() throws {
        let kivy = try KivyLikeClient(width: 4, height: 4)
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        var name: GLuint = 0
        kivy.t.glGenTextures!(1, &name)
        kivy.t.glBindTexture!(GL.texture2D, name)
        kivy.t.glTexParameteri!(GL.texture2D, GL.textureMinFilter, GLint(GL.nearest))
        kivy.t.glTexParameteri!(GL.texture2D, GL.textureMagFilter, GLint(GL.nearest))
        kivy.t.glPixelStorei!(GL.unpackAlignment, 1)
        kivy.t.glTexImage2D!(GL.texture2D, 0, GLint(GL.rgb), 1, 1, 0, GL.rgb, GL.unsignedByte, [10, 20, 30] as [UInt8])
        kivy.rectangle(program, x: 0, y: 0, width: 4, height: 4)
        #expect(kivy.pixel(kivy.read(), x: 1, y: 1) == SIMD4(10, 20, 30, 255))

        kivy.t.glTexImage2D!(GL.texture2D, 0, GLint(GL.luminance), 1, 1, 0, GL.luminance, GL.unsignedByte, [77] as [UInt8])
        kivy.rectangle(program, x: 0, y: 0, width: 4, height: 4)
        #expect(kivy.pixel(kivy.read(), x: 1, y: 1) == SIMD4(77, 77, 77, 255))

        kivy.t.glTexImage2D!(GL.texture2D, 0, GLint(GL.rgba), 1, 1, 0, GL.bgra, GL.unsignedByte, [1, 2, 3, 255] as [UInt8])
        kivy.rectangle(program, x: 0, y: 0, width: 4, height: 4)
        #expect(kivy.pixel(kivy.read(), x: 1, y: 1) == SIMD4(3, 2, 1, 255))
    }

    @Test func triangleFanAndLineLoopDraw() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program, color: SIMD4(0, 1, 0, 1))
        kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])
        // Kivy's Mesh(mode='triangle_fan').
        kivy.rectangle(program, x: 0, y: 0, width: 32, height: 32, mode: GL.triangleFan, indices: [0, 1, 2, 3])
        // And a line loop around the top-right quarter.
        kivy.rectangle(program, x: 40.5, y: 40.5, width: 16, height: 16, mode: GL.lineLoop, indices: [0, 1, 2, 3])
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 10, y: 20) == green)
        #expect(kivy.pixel(pixels, x: 20, y: 10) == green)
        #expect(kivy.pixel(pixels, x: 40, y: 48) == green)
        #expect(kivy.pixel(pixels, x: 48, y: 48) == black)
    }

    @Test func blendingMixesLikeKivy() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 1, 1))
        let program = kivy.kivyProgram()
        kivy.t.glEnable!(GL.blend)
        kivy.t.glBlendFunc!(GL.srcAlpha, GL.oneMinusSrcAlpha)
        kivy.setupProjection(program, color: SIMD4(1, 0, 0, 0.5))
        kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixel = kivy.pixel(kivy.read(), x: 32, y: 32)
        #expect(abs(Int(pixel.x) - 128) <= 2)
        #expect(pixel.y == 0)
        #expect(abs(Int(pixel.z) - 128) <= 2)
    }

    @Test func fboRendersIntoATextureKivyThenDraws() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()

        // Kivy's Fbo: a texture and a depth+stencil renderbuffer.
        let colorTexture = kivy.texture(width: 16, height: 16, pixels: [UInt8](repeating: 0, count: 16 * 16 * 4))
        var framebuffer: GLuint = 0, renderbuffer: GLuint = 0
        kivy.t.glGenFramebuffers!(1, &framebuffer)
        kivy.t.glBindFramebuffer!(GL.framebuffer, framebuffer)
        kivy.t.glGenRenderbuffers!(1, &renderbuffer)
        kivy.t.glBindRenderbuffer!(GL.renderbuffer, renderbuffer)
        kivy.t.glRenderbufferStorage!(GL.renderbuffer, GL.depth24Stencil8Oes, 16, 16)
        kivy.t.glFramebufferRenderbuffer!(GL.framebuffer, GL.depthStencilAttachment, GL.renderbuffer, renderbuffer)
        kivy.t.glFramebufferTexture2D!(GL.framebuffer, GL.colorAttachment0, GL.texture2D, colorTexture, 0)
        #expect(kivy.t.glCheckFramebufferStatus!(GL.framebuffer) == GL.framebufferComplete)

        // Inside the Fbo: green, then a red bottom half.
        kivy.t.glViewport!(0, 0, 16, 16)
        kivy.clear(SIMD4(0, 1, 0, 1))
        kivy.setupProjection(program, color: SIMD4(1, 0, 0, 1), width: 16, height: 16)
        kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])
        kivy.rectangle(program, x: 0, y: 0, width: 16, height: 8)

        // Back on the window: the Fbo's texture over the whole of it.
        kivy.t.glBindFramebuffer!(GL.framebuffer, 0)
        kivy.t.glViewport!(0, 0, 64, 64)
        kivy.clear(SIMD4(0, 0, 0, 1))
        kivy.setupProjection(program)
        kivy.t.glBindTexture!(GL.texture2D, colorTexture)
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 32, y: 10) == red)
        #expect(kivy.pixel(pixels, x: 32, y: 50) == green)
    }

    @Test func stencilPushUseLikeKivyClipsDrawing() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program, color: SIMD4(1, 1, 1, 1))
        kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])

        // StencilPush: write 1 where the mask shape is, no color.
        kivy.t.glEnable!(GL.stencilTest)
        kivy.t.glStencilMask!(0xFF)
        kivy.t.glStencilFunc!(GL.always, 1, 0xFF)
        kivy.t.glStencilOp!(GL.keep, GL.keep, GL.replace)
        kivy.t.glColorMask!(0, 0, 0, 0)
        kivy.rectangle(program, x: 0, y: 0, width: 32, height: 64)
        // StencilUse: draw only where it is 1.
        kivy.t.glColorMask!(1, 1, 1, 1)
        kivy.t.glStencilFunc!(GL.equal, 1, 0xFF)
        kivy.t.glStencilOp!(GL.keep, GL.keep, GL.keep)
        kivy.setupProjection(program, color: SIMD4(0, 0, 1, 1))
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        kivy.t.glDisable!(GL.stencilTest)

        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 10, y: 32) == blue)
        #expect(kivy.pixel(pixels, x: 50, y: 32) == black)
    }

    @Test func presentCopiesFramebufferZeroFlippedForTheComposite() throws {
        let kivy = try KivyLikeClient()
        // Bottom half red, top half green, in GL's terms.
        kivy.clear(SIMD4(0, 1, 0, 1))
        kivy.t.glEnable!(GL.scissorTest)
        kivy.t.glScissor!(0, 0, 64, 32)
        kivy.t.glClearColor!(1, 0, 0, 1)
        kivy.t.glClear!(GL.colorBufferBit)
        kivy.t.glDisable!(GL.scissorTest)

        let target = try GLImage(
            device: kivy.gl.device, width: 64, height: 64, format: KivyGL.colorFormat,
            usage: KivyGL.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        )
        defer { target.destroy() }
        kivy.gl.presentTarget = (target.image, 64, 64, VK_IMAGE_LAYOUT_UNDEFINED)
        kivy.gl.present()

        // Read the node's image the way the composite sees it: row 0 on top.
        target.layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        let texture = GLTexture()
        texture.image = target
        kivy.gl.textures[9999] = texture
        var framebuffer: GLuint = 0
        kivy.t.glGenFramebuffers!(1, &framebuffer)
        kivy.t.glBindFramebuffer!(GL.framebuffer, framebuffer)
        kivy.t.glFramebufferTexture2D!(GL.framebuffer, GL.colorAttachment0, GL.texture2D, 9999, 0)
        let pixels = kivy.read()
        kivy.gl.textures[9999] = nil
        #expect(kivy.pixel(pixels, x: 10, y: 10) == green)
        #expect(kivy.pixel(pixels, x: 10, y: 50) == red)
    }

    @Test func compileErrorsReachTheInfoLog() throws {
        let kivy = try KivyLikeClient()
        let shader = kivy.t.glCreateShader!(GL.fragmentShader)
        "void main() { gl_FragColor = undefined_thing; }".withCString { pointer in
            var string: UnsafePointer<CChar>? = pointer
            kivy.t.glShaderSource!(shader, 1, &string, nil)
        }
        kivy.t.glCompileShader!(shader)
        var status: GLint = 1
        kivy.t.glGetShaderiv!(shader, GL.compileStatus, &status)
        #expect(status == 0)
        #expect(kivy.log(shader: shader).contains("undefined_thing"))
    }

    @Test func getStringAnswersAsGLES2() throws {
        let kivy = try KivyLikeClient()
        let version = String(cString: UnsafeRawPointer(kivy.t.glGetString!(GL.version)!).assumingMemoryBound(to: CChar.self))
        #expect(version.hasPrefix("OpenGL ES 2.0"))
        let extensions = String(cString: UnsafeRawPointer(kivy.t.glGetString!(GL.extensions)!).assumingMemoryBound(to: CChar.self))
        #expect(extensions.contains("GL_EXT_bgra"))
        #expect(extensions.contains("GL_OES_standard_derivatives"))
    }

    /// GLSL ES 1.00 asks for derivatives with an extension; Vulkan GLSL has
    /// them built in. The fill below is opaque only where the screen-space
    /// slope of x is one pixel per pixel, which it is for a 1:1 rectangle.
    @Test func standardDerivativesCompileAndMeasurePixels() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let fragment = """
        #extension GL_OES_standard_derivatives : enable
        #ifdef GL_ES
            precision highp float;
        #endif
        varying vec4 frag_color;
        varying vec2 tex_coord0;
        uniform sampler2D texture0;
        void main (void){
            float slope = dFdx(gl_FragCoord.x) + fwidth(gl_FragCoord.y) - 1.0;
            gl_FragColor = vec4(1.0 - abs(slope - 1.0), 0.0, 0.0, 1.0);
        }
        """
        let program = kivy.kivyProgram(fragment: fragment)
        kivy.setupProjection(program)
        kivy.rectangle(program, x: 0, y: 0, width: 32, height: 32)
        let pixels = kivy.read()
        #expect(kivy.pixel(pixels, x: 16, y: 16) == red)
        #expect(kivy.error == GL.noError)
    }

    // MARK: - Skia into textures

    /// Skia draws into the texture's own image; Kivy samples it as it does
    /// any texture. Skia's first row is the texture's row 0, which Kivy's
    /// unflipped texture coordinates put at the bottom.
    @Test func skiaDrawsIntoAKivyTextureThatKivyThenSamples() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        let name = kivy.texture(width: 64, height: 64, pixels: [UInt8](repeating: 255, count: 64 * 64 * 4))
        try kivy.gl.drawWithSkia(texture: name) { canvas in
            canvas.clear(SIMD4<Float>(1, 0, 0, 1))
            canvas.drawRect(x: 0, y: 0, w: 64, h: 16, paint: SkPaint(color: SIMD4(0, 0, 1, 1)))
        }
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 32, y: 8) == blue)
        #expect(kivy.pixel(pixels, x: 32, y: 40) == red)
    }

    /// Skia draws over what Kivy uploaded, Kivy uploads over what Skia drew,
    /// and Skia draws again on the same surface: each keeps the other's
    /// pixels outside what it touched.
    @Test func skiaAndKivyUploadsDrawOverEachOther() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        let greenPixels: [UInt8] = (0..<64 * 64).flatMap { _ in [0, 255, 0, 255] as [UInt8] }
        let name = kivy.texture(width: 64, height: 64, pixels: greenPixels)
        try kivy.gl.drawWithSkia(texture: name) { canvas in
            canvas.drawRect(x: 0, y: 0, w: 32, h: 64, paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
        }
        let bluePixels: [UInt8] = (0..<16 * 16).flatMap { _ in [0, 0, 255, 255] as [UInt8] }
        kivy.t.glTexSubImage2D!(GL.texture2D, 0, 48, 0, 16, 16, GL.rgba, GL.unsignedByte, bluePixels)
        try kivy.gl.drawWithSkia(texture: name) { canvas in
            canvas.drawRect(x: 0, y: 48, w: 16, h: 16, paint: SkPaint(color: SIMD4(1, 1, 1, 1)))
        }
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 24, y: 40) == red)
        #expect(kivy.pixel(pixels, x: 40, y: 40) == green)
        #expect(kivy.pixel(pixels, x: 56, y: 8) == blue)
        #expect(kivy.pixel(pixels, x: 8, y: 56) == white)
        #expect(kivy.pixel(pixels, x: 24, y: 56) == red)
    }

    /// The texture of a Kivy Fbo: Kivy renders into it, Skia draws over that
    /// before the frame is submitted, then Kivy renders into it again.
    @Test func skiaDrawsBetweenKivysPassesIntoAnFboTexture() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        let colorTexture = kivy.texture(width: 16, height: 16, pixels: [UInt8](repeating: 0, count: 16 * 16 * 4))
        var framebuffer: GLuint = 0
        kivy.t.glGenFramebuffers!(1, &framebuffer)
        kivy.t.glBindFramebuffer!(GL.framebuffer, framebuffer)
        kivy.t.glFramebufferTexture2D!(GL.framebuffer, GL.colorAttachment0, GL.texture2D, colorTexture, 0)
        kivy.t.glViewport!(0, 0, 16, 16)
        kivy.clear(SIMD4(0, 1, 0, 1))

        try kivy.gl.drawWithSkia(texture: colorTexture) { canvas in
            canvas.drawRect(x: 0, y: 0, w: 16, h: 8, paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
        }

        kivy.setupProjection(program, color: SIMD4(0, 0, 1, 1), width: 16, height: 16)
        let white1x1 = kivy.texture(width: 1, height: 1, pixels: [255, 255, 255, 255])
        kivy.rectangle(program, x: 0, y: 12, width: 16, height: 4)

        kivy.t.glBindFramebuffer!(GL.framebuffer, 0)
        kivy.t.glViewport!(0, 0, 64, 64)
        kivy.clear(SIMD4(0, 0, 0, 1))
        kivy.setupProjection(program)
        kivy.t.glBindTexture!(GL.texture2D, colorTexture)
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 32, y: 10) == red)
        #expect(kivy.pixel(pixels, x: 32, y: 40) == green)
        #expect(kivy.pixel(pixels, x: 32, y: 60) == blue)
        var names = [white1x1]
        kivy.t.glDeleteTextures!(1, &names)
    }

    /// A deleted texture takes its Skia surface with it; a new one gets its
    /// own. Names with no image, and mipmapped textures, are refused.
    @Test func skiaSurfacesFollowTheirTextures() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)

        #expect(throws: KivySkiaError.self) {
            try kivy.gl.drawWithSkia(texture: 999) { _ in }
        }
        let mipmapped = kivy.texture(width: 8, height: 8, pixels: [UInt8](repeating: 255, count: 8 * 8 * 4))
        kivy.t.glGenerateMipmap!(GL.texture2D)
        #expect(throws: KivySkiaError.self) {
            try kivy.gl.drawWithSkia(texture: mipmapped) { _ in }
        }

        var first = kivy.texture(width: 32, height: 32, pixels: [UInt8](repeating: 0, count: 32 * 32 * 4))
        try kivy.gl.drawWithSkia(texture: first) { $0.clear(SIMD4<Float>(1, 0, 0, 1)) }
        kivy.t.glDeleteTextures!(1, &first)
        let second = kivy.texture(width: 32, height: 32, pixels: [UInt8](repeating: 0, count: 32 * 32 * 4))
        try kivy.gl.drawWithSkia(texture: second) { $0.clear(SIMD4<Float>(0, 1, 0, 1)) }
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 32, y: 32) == green)
    }

    // MARK: - Text and images for Kivy's providers

    static let roboto = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("kivy2x/kivy/data/fonts/Roboto-Regular.ttf").path

    /// 2x2 RGBA: red, green / blue, white at half alpha.
    static let png: [UInt8] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x08, 0x06, 0x00, 0x00, 0x00, 0x72, 0xb6, 0x0d,
        0x24, 0x00, 0x00, 0x00, 0x19, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x05, 0xc1, 0x01, 0x0d, 0x00,
        0x00, 0x08, 0xc0, 0x20, 0xdc, 0x2c, 0x6e, 0xf2, 0x0b, 0x22, 0x69, 0x47, 0xe2, 0x1e, 0x3f, 0x80,
        0x06, 0x81, 0xa3, 0x55, 0xfe, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42,
        0x60, 0x82,
    ]

    func withFont<R>(size: Float, underline: Bool = false, outline: Float = 0, _ body: (KivyNUIFont) throws -> R) rethrows -> R {
        try Self.roboto.withCString { path in
            try body(KivyNUIFont(
                path: path, size: size, hinting: 2, antialias: true,
                underline: underline, strikethrough: false, outline_width: outline
            ))
        }
    }

    @Test func providersMeasureTextWithTheFontFile() throws {
        let providers = KivyProviders()
        let metrics = try #require(withFont(size: 32) { providers.metrics($0) })
        #expect(metrics.ascent > 20 && metrics.ascent < 40 && metrics.descent > 4 && metrics.descent < 16)
        let short = try #require(withFont(size: 32) { providers.extents($0, "Hi") })
        let long = try #require(withFont(size: 32) { providers.extents($0, "Hi there") })
        #expect(short.height == metrics.ascent + metrics.descent)
        #expect(long.width > short.width && long.height == short.height)
        let outlined = try #require(withFont(size: 32, outline: 3) { providers.extents($0, "Hi") })
        #expect(outlined.width == short.width + 6 && outlined.height == short.height + 6)
        let missing = "/nonexistent.ttf".withCString { path in
            providers.extents(KivyNUIFont(path: path, size: 32, hinting: 2, antialias: true,
                                          underline: false, strikethrough: false, outline_width: 0), "Hi")
        }
        #expect(missing == nil)
    }

    /// A label's texture before Kivy has given it storage (a power-of-two
    /// size made with a fill callback): the host makes it, clears it and
    /// draws the runs. An underlined run of spaces is a bar of the text's
    /// color under where the glyphs would be.
    @Test func providersDrawTextRunsIntoATexture() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        var name: GLuint = 0
        kivy.t.glGenTextures!(1, &name)
        kivy.t.glBindTexture!(GL.texture2D, name)
        let providers = KivyProviders()
        try withFont(size: 24, underline: true) { font in
            try "        ".withCString { spaces in
                var run = KivyNUITextRun()
                run.utf8 = spaces
                run.x = 4
                run.y = 4
                run.color = (1, 0, 0, 1)
                run.outline_color = (0, 0, 0, 1)
                run.font = font
                try withUnsafePointer(to: &run) { pointer in
                    try providers.drawText(UnsafeBufferPointer(start: pointer, count: 1),
                                           texture: name, width: 64, height: 64, gl: kivy.gl)
                }
            }
        }
        #expect(kivy.gl.textures[name]?.image?.width == 64)
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        // The bar is a few rows somewhere below the baseline (about y 32 down
        // from the top: texture rows, which Kivy's unflipped rectangle shows
        // from the bottom).
        let rows = (0..<64).filter { y in kivy.pixel(pixels, x: 20, y: y) == red }
        #expect(!rows.isEmpty && rows.count <= 3, "\(rows)")
        #expect(rows.allSatisfy { $0 > 26 && $0 < 40 }, "\(rows)")
        // Cleared: transparent (no blending here, so read back as it is).
        #expect(kivy.pixel(pixels, x: 20, y: 60) == .zero)
    }

    @Test func providersDecodeAndDrawImages() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        let providers = KivyProviders()
        try Self.png.withUnsafeBytes { data in
            let size = try #require(providers.imageSize(data))
            #expect(size.width == 2 && size.height == 2)
            var pixels = [UInt8](repeating: 0, count: 16)
            #expect(pixels.withUnsafeMutableBytes { providers.imagePixels(data, into: $0) })
            #expect(pixels == [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 128])
            // The wrong buffer size is refused.
            var small = [UInt8](repeating: 0, count: 8)
            #expect(!small.withUnsafeMutableBytes { providers.imagePixels(data, into: $0) })

            var name: GLuint = 0
            kivy.t.glGenTextures!(1, &name)
            kivy.t.glBindTexture!(GL.texture2D, name)
            kivy.t.glTexParameteri!(GL.texture2D, GL.textureMinFilter, GLint(GL.nearest))
            kivy.t.glTexParameteri!(GL.texture2D, GL.textureMagFilter, GLint(GL.nearest))
            #expect(try providers.drawImage(data, texture: name, width: 2, height: 2, gl: kivy.gl))
        }
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        // The image's first row is the texture's row 0: the bottom here.
        #expect(kivy.pixel(pixels, x: 10, y: 10) == red)
        #expect(kivy.pixel(pixels, x: 50, y: 10) == green)
        #expect(kivy.pixel(pixels, x: 10, y: 50) == blue)
        // Not an image.
        let junk: [UInt8] = [1, 2, 3, 4]
        #expect(junk.withUnsafeBytes { providers.imageSize($0) } == nil)
    }

    /// A mipmapped texture (Kivy's `mipmap=True`) is filled through one level
    /// and keeps its mipmaps.
    @Test func fillWithSkiaKeepsAMipmappedTexturesMipmaps() throws {
        let kivy = try KivyLikeClient()
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        let name = kivy.texture(width: 16, height: 16, pixels: [UInt8](repeating: 255, count: 16 * 16 * 4))
        kivy.t.glGenerateMipmap!(GL.texture2D)
        let levels = try #require(kivy.gl.textures[name]?.image?.levels)
        #expect(levels == 5)
        try kivy.gl.fillWithSkia(texture: name, width: 16, height: 16) { $0.clear(SIMD4<Float>(0, 0, 1, 1)) }
        #expect(kivy.gl.textures[name]?.image?.levels == levels)
        kivy.t.glTexParameteri!(GL.texture2D, GL.textureMinFilter, GLint(GL.nearestMipmapNearest))
        kivy.rectangle(program, x: 0, y: 0, width: 4, height: 4)
        kivy.rectangle(program, x: 8, y: 8, width: 56, height: 56)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        #expect(kivy.pixel(pixels, x: 2, y: 2) == blue)
        #expect(kivy.pixel(pixels, x: 30, y: 30) == blue)
    }

    /// An SVG with only a viewBox: sized by it, drawn into the texture, and
    /// decoded to straight-alpha bytes for `keep_data`.
    @Test func providersDrawSVGDocuments() throws {
        let kivy = try KivyLikeClient()
        kivy.clear(SIMD4(0, 0, 0, 1))
        let program = kivy.kivyProgram()
        kivy.setupProjection(program)
        let providers = KivyProviders()
        let svg = Array("""
            <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 8 4'>
              <rect width='8' height='2' fill='#ff0000'/>
              <rect y='2' width='8' height='2' fill='#0000ff'/>
            </svg>
            """.utf8)
        try svg.withUnsafeBytes { data in
            let size = try #require(providers.imageSize(data))
            #expect(size.width == 8 && size.height == 4)
            var pixels = [UInt8](repeating: 0, count: 8 * 4 * 4)
            #expect(pixels.withUnsafeMutableBytes { providers.imagePixels(data, into: $0) })
            #expect(Array(pixels[0..<4]) == [255, 0, 0, 255])
            #expect(Array(pixels[(3 * 8) * 4..<(3 * 8) * 4 + 4]) == [0, 0, 255, 255])

            var name: GLuint = 0
            kivy.t.glGenTextures!(1, &name)
            kivy.t.glBindTexture!(GL.texture2D, name)
            kivy.t.glTexParameteri!(GL.texture2D, GL.textureMinFilter, GLint(GL.nearest))
            kivy.t.glTexParameteri!(GL.texture2D, GL.textureMagFilter, GLint(GL.nearest))
            #expect(try providers.drawImage(data, texture: name, width: 8, height: 4, gl: kivy.gl))
        }
        kivy.rectangle(program, x: 0, y: 0, width: 64, height: 64)
        let pixels = kivy.read()
        #expect(kivy.error == GL.noError)
        // The document's top is the texture's row 0: the bottom here.
        #expect(kivy.pixel(pixels, x: 32, y: 10) == red)
        #expect(kivy.pixel(pixels, x: 32, y: 54) == blue)
    }
}
