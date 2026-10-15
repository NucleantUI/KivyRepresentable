import Testing
import CKivyNUI
import CVulkan
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
    }
}
