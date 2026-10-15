//
//  KivyGL+Table.swift
//  KivyRepresentable
//
//  The `KivyNUIGL` table Kivy calls: every member forwards to
//  `KivyGL.current`. Members left nil are what this GL doesn't do yet —
//  `cgl_nui.pyx` reports them, and Kivy's `gl_check` logs any it reaches.
//

import CKivyNUI

extension KivyGL {

    /// The table to register with the shared C api (`KivyNUIHost.gl`). It
    /// holds no context of its own — set `KivyGL.current` before Kivy draws.
    nonisolated(unsafe) public static let table: UnsafeMutablePointer<KivyNUIGL> = {
        let table = UnsafeMutablePointer<KivyNUIGL>.allocate(capacity: 1)
        table.initialize(to: makeTable())
        return table
    }()

    private static func copyString(_ string: String, _ bufSize: GLsizei, _ length: UnsafeMutablePointer<GLsizei>?, _ out: UnsafeMutablePointer<CChar>?) {
        guard let out, bufSize > 0 else {
            length?.pointee = 0
            return
        }
        let bytes = Array(string.utf8.prefix(Int(bufSize) - 1))
        for (index, byte) in bytes.enumerated() { out[index] = CChar(bitPattern: byte) }
        out[bytes.count] = 0
        length?.pointee = GLsizei(bytes.count)
    }

    private static func string(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }

    private static func makeTable() -> KivyNUIGL {
        var t = KivyNUIGL()

        // MARK: Strings, errors, queries
        t.glGetString = { KivyGL.current?.getString($0) }
        t.glGetError = { KivyGL.current?.getError() ?? GL.noError }
        t.glGetIntegerv = { pname, out in
            guard let gl = KivyGL.current, let out else { return }
            guard let values = gl.getIntegers(pname) else { return gl.setError(GL.invalidEnum) }
            for (index, value) in values.enumerated() { out[index] = value }
        }
        t.glGetFloatv = { pname, out in
            guard let gl = KivyGL.current, let out else { return }
            guard let values = gl.getFloats(pname) else { return gl.setError(GL.invalidEnum) }
            for (index, value) in values.enumerated() { out[index] = value }
        }
        t.glGetBooleanv = { pname, out in
            guard let gl = KivyGL.current, let out else { return }
            guard let values = gl.getFloats(pname) else { return gl.setError(GL.invalidEnum) }
            for (index, value) in values.enumerated() { out[index] = value != 0 ? 1 : 0 }
        }
        t.glIsEnabled = { KivyGL.current?.isEnabled($0) ?? 0 }
        t.glEnable = { KivyGL.current?.setCapability($0, true) }
        t.glDisable = { KivyGL.current?.setCapability($0, false) }
        t.glHint = { _, _ in }
        t.glFlush = { }
        t.glFinish = { KivyGL.current?.frame.submit() }

        // MARK: Buffers
        t.glGenBuffers = { KivyGL.current?.genBuffers($0, $1) }
        t.glDeleteBuffers = { KivyGL.current?.deleteBuffers($0, $1) }
        t.glIsBuffer = { name in KivyGL.current.map { $0.buffers[name] != nil ? 1 : 0 } ?? 0 }
        t.glBindBuffer = { KivyGL.current?.bindBuffer($0, $1) }
        t.glBufferData = { KivyGL.current?.bufferData($0, Int($1), $2, $3) }
        t.glBufferSubData = { KivyGL.current?.bufferSubData($0, Int($1), Int($2), $3) }
        t.glGetBufferParameteriv = { target, pname, out in
            guard let gl = KivyGL.current, let out else { return }
            let name = target == GL.arrayBuffer ? gl.arrayBuffer : target == GL.elementArrayBuffer ? gl.elementArrayBuffer : 0
            guard let buffer = gl.buffers[name] else { return gl.setError(GL.invalidOperation) }
            switch pname {
            case GL.bufferSize: out.pointee = GLint(buffer.data.count)
            case GL.bufferUsage: out.pointee = GLint(buffer.usage)
            default: gl.setError(GL.invalidEnum)
            }
        }

        // MARK: Vertex attributes
        t.glVertexAttribPointer = { KivyGL.current?.vertexAttribPointer($0, $1, $2, $3, $4, $5) }
        t.glEnableVertexAttribArray = { KivyGL.current?.setVertexAttribArray($0, enabled: true) }
        t.glDisableVertexAttribArray = { KivyGL.current?.setVertexAttribArray($0, enabled: false) }
        t.glVertexAttrib1f = { KivyGL.current?.vertexAttrib($0, SIMD4($1, 0, 0, 1)) }
        t.glVertexAttrib2f = { KivyGL.current?.vertexAttrib($0, SIMD4($1, $2, 0, 1)) }
        t.glVertexAttrib3f = { KivyGL.current?.vertexAttrib($0, SIMD4($1, $2, $3, 1)) }
        t.glVertexAttrib4f = { KivyGL.current?.vertexAttrib($0, SIMD4($1, $2, $3, $4)) }
        t.glGetVertexAttribfv = { index, pname, out in
            guard let gl = KivyGL.current, let out, Int(index) < KivyGL.maxVertexAttributes else { return }
            let attribute = gl.vertexAttributes[Int(index)]
            if pname == GL.currentVertexAttrib {
                for i in 0..<4 { out[i] = attribute.current[i] }
            } else if let value = KivyGL.vertexAttribValue(attribute, pname) {
                out.pointee = GLfloat(value)
            } else {
                gl.setError(GL.invalidEnum)
            }
        }
        t.glGetVertexAttribiv = { index, pname, out in
            guard let gl = KivyGL.current, let out, Int(index) < KivyGL.maxVertexAttributes else { return }
            let attribute = gl.vertexAttributes[Int(index)]
            if pname == GL.currentVertexAttrib {
                for i in 0..<4 { out[i] = GLint(attribute.current[i]) }
            } else if let value = KivyGL.vertexAttribValue(attribute, pname) {
                out.pointee = value
            } else {
                gl.setError(GL.invalidEnum)
            }
        }

        // MARK: Textures
        t.glGenTextures = { KivyGL.current?.genTextures($0, $1) }
        t.glDeleteTextures = { KivyGL.current?.deleteTextures($0, $1) }
        t.glIsTexture = { name in KivyGL.current.map { $0.textures[name] != nil ? 1 : 0 } ?? 0 }
        t.glActiveTexture = { KivyGL.current?.setActiveTexture($0) }
        t.glBindTexture = { KivyGL.current?.bindTexture($0, $1) }
        t.glTexImage2D = { KivyGL.current?.texImage2D($0, $1, $2, $3, $4, $5, $6, $7, $8) }
        t.glTexSubImage2D = { KivyGL.current?.texSubImage2D($0, $1, $2, $3, $4, $5, $6, $7, $8) }
        t.glTexParameteri = { KivyGL.current?.texParameter($0, $1, $2) }
        t.glTexParameterf = { KivyGL.current?.texParameter($0, $1, GLint($2)) }
        t.glGetTexParameteriv = { target, pname, out in
            guard let value = KivyGL.current?.getTexParameter(target, pname) else { return }
            out?.pointee = value
        }
        t.glGetTexParameterfv = { target, pname, out in
            guard let value = KivyGL.current?.getTexParameter(target, pname) else { return }
            out?.pointee = GLfloat(value)
        }
        t.glGenerateMipmap = { KivyGL.current?.generateMipmap($0) }
        t.glPixelStorei = { KivyGL.current?.pixelStore($0, $1) }

        // MARK: Framebuffers and renderbuffers
        t.glGenFramebuffers = { KivyGL.current?.genFramebuffers($0, $1) }
        t.glDeleteFramebuffers = { KivyGL.current?.deleteFramebuffers($0, $1) }
        t.glIsFramebuffer = { name in KivyGL.current.map { $0.framebuffers[name] != nil ? 1 : 0 } ?? 0 }
        t.glBindFramebuffer = { KivyGL.current?.bindFramebuffer($0, $1) }
        t.glFramebufferTexture2D = { KivyGL.current?.framebufferTexture2D($0, $1, $2, $3, $4) }
        t.glFramebufferRenderbuffer = { KivyGL.current?.framebufferRenderbuffer($0, $1, $2, $3) }
        t.glCheckFramebufferStatus = { KivyGL.current?.checkFramebufferStatus($0) ?? 0 }
        t.glGetFramebufferAttachmentParameteriv = { _, attachment, pname, out in
            guard let value = KivyGL.current?.getFramebufferAttachmentParameter(attachment, pname) else { return }
            out?.pointee = value
        }
        t.glGenRenderbuffers = { KivyGL.current?.genRenderbuffers($0, $1) }
        t.glDeleteRenderbuffers = { KivyGL.current?.deleteRenderbuffers($0, $1) }
        t.glIsRenderbuffer = { name in KivyGL.current.map { $0.renderbuffers[name] != nil ? 1 : 0 } ?? 0 }
        t.glBindRenderbuffer = { KivyGL.current?.bindRenderbuffer($0, $1) }
        t.glRenderbufferStorage = { KivyGL.current?.renderbufferStorage($0, $1, $2, $3) }
        t.glGetRenderbufferParameteriv = { _, pname, out in
            guard let value = KivyGL.current?.getRenderbufferParameter(pname) else { return }
            out?.pointee = value
        }

        // MARK: Shaders and programs
        t.glCreateShader = { KivyGL.current?.createShader($0) ?? 0 }
        t.glShaderSource = { KivyGL.current?.shaderSource($0, $1, $2, $3) }
        t.glCompileShader = { KivyGL.current?.compileShader($0) }
        t.glDeleteShader = { KivyGL.current?.deleteShader($0) }
        t.glIsShader = { name in KivyGL.current.map { $0.shaders[name] != nil ? 1 : 0 } ?? 0 }
        t.glGetShaderiv = { name, pname, out in
            guard let value = KivyGL.current?.getShader(name, pname) else { return }
            out?.pointee = value
        }
        t.glGetShaderInfoLog = { name, bufSize, length, out in
            guard let log = KivyGL.current?.shaderInfoLog(name) else { return }
            KivyGL.copyString(log, bufSize, length, out)
        }
        t.glGetShaderSource = { name, bufSize, length, out in
            guard let source = KivyGL.current?.shaderSourceText(name) else { return }
            KivyGL.copyString(source, bufSize, length, out)
        }
        t.glCreateProgram = { KivyGL.current?.createProgram() ?? 0 }
        t.glDeleteProgram = { KivyGL.current?.deleteProgram($0) }
        t.glIsProgram = { name in KivyGL.current.map { $0.programs[name] != nil ? 1 : 0 } ?? 0 }
        t.glAttachShader = { KivyGL.current?.attachShader($0, $1) }
        t.glDetachShader = { KivyGL.current?.detachShader($0, $1) }
        t.glBindAttribLocation = { KivyGL.current?.bindAttribLocation($0, $1, KivyGL.string($2)) }
        t.glLinkProgram = { KivyGL.current?.linkProgram($0) }
        t.glValidateProgram = { _ in }
        t.glUseProgram = { KivyGL.current?.useProgram($0) }
        t.glGetProgramiv = { name, pname, out in
            guard let value = KivyGL.current?.getProgram(name, pname) else { return }
            out?.pointee = value
        }
        t.glGetProgramInfoLog = { name, bufSize, length, out in
            guard let log = KivyGL.current?.programInfoLog(name) else { return }
            KivyGL.copyString(log, bufSize, length, out)
        }
        t.glGetAttachedShaders = { name, maxCount, count, out in
            guard let program = KivyGL.current?.programs[name] else { return }
            let shaders = program.shaders.prefix(Int(max(0, maxCount)))
            for (index, shader) in shaders.enumerated() { out?[index] = shader }
            count?.pointee = GLsizei(shaders.count)
        }
        t.glGetAttribLocation = { KivyGL.current?.getAttribLocation($0, KivyGL.string($1)) ?? -1 }
        t.glGetUniformLocation = { KivyGL.current?.getUniformLocation($0, KivyGL.string($1)) ?? -1 }
        t.glGetActiveAttrib = { name, index, bufSize, length, size, type, out in
            guard let gl = KivyGL.current, let program = gl.programs[name], Int(index) < program.attributes.count else {
                return KivyGL.current?.setError(GL.invalidValue) ?? ()
            }
            let attribute = program.attributes[Int(index)].variable
            size?.pointee = GLint(attribute.count)
            type?.pointee = attribute.type.glType
            KivyGL.copyString(attribute.name, bufSize, length, out)
        }
        t.glGetActiveUniform = { name, index, bufSize, length, size, type, out in
            guard let gl = KivyGL.current, let program = gl.programs[name], Int(index) < program.uniforms.count else {
                return KivyGL.current?.setError(GL.invalidValue) ?? ()
            }
            let uniform = program.uniforms[Int(index)].variable
            size?.pointee = GLint(uniform.count)
            type?.pointee = uniform.type.glType
            KivyGL.copyString(gl.activeName(uniform), bufSize, length, out)
        }
        t.glGetUniformfv = { name, location, out in
            guard let values = KivyGL.current?.getUniform(name, location), let out else { return }
            for (index, value) in values.enumerated() { out[index] = value }
        }
        t.glGetUniformiv = { name, location, out in
            guard let values = KivyGL.current?.getUniform(name, location), let out else { return }
            for (index, value) in values.enumerated() { out[index] = GLint(value) }
        }

        // MARK: Uniforms
        t.glUniform1f = { location, x in
            KivyGL.current?.setUniform(location, count: 1, components: 1, float: { _ in x }, int: nil)
        }
        t.glUniform2f = { location, x, y in
            KivyGL.current?.setUniform(location, count: 1, components: 2, float: { [x, y][$0] }, int: nil)
        }
        t.glUniform3f = { location, x, y, z in
            KivyGL.current?.setUniform(location, count: 1, components: 3, float: { [x, y, z][$0] }, int: nil)
        }
        t.glUniform4f = { location, x, y, z, w in
            KivyGL.current?.setUniform(location, count: 1, components: 4, float: { [x, y, z, w][$0] }, int: nil)
        }
        t.glUniform1i = { location, x in
            KivyGL.current?.setUniform(location, count: 1, components: 1, float: nil, int: { _ in x })
        }
        t.glUniform2i = { location, x, y in
            KivyGL.current?.setUniform(location, count: 1, components: 2, float: nil, int: { [x, y][$0] })
        }
        t.glUniform3i = { location, x, y, z in
            KivyGL.current?.setUniform(location, count: 1, components: 3, float: nil, int: { [x, y, z][$0] })
        }
        t.glUniform4i = { location, x, y, z, w in
            KivyGL.current?.setUniform(location, count: 1, components: 4, float: nil, int: { [x, y, z, w][$0] })
        }
        t.glUniform1fv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 1, float: { v[$0] }, int: nil)
        }
        t.glUniform2fv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 2, float: { v[$0] }, int: nil)
        }
        t.glUniform3fv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 3, float: { v[$0] }, int: nil)
        }
        t.glUniform4fv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 4, float: { v[$0] }, int: nil)
        }
        t.glUniform1iv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 1, float: nil, int: { v[$0] })
        }
        t.glUniform2iv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 2, float: nil, int: { v[$0] })
        }
        t.glUniform3iv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 3, float: nil, int: { v[$0] })
        }
        t.glUniform4iv = { location, count, v in
            guard let v else { return }
            KivyGL.current?.setUniform(location, count: count, components: 4, float: nil, int: { v[$0] })
        }
        t.glUniformMatrix4fv = { location, count, transpose, v in
            KivyGL.current?.setUniformMatrix(location, count: count, size: 4, transpose: transpose != 0, values: v)
        }

        // MARK: Fixed-function state
        t.glViewport = { x, y, width, height in
            guard let gl = KivyGL.current else { return }
            guard width >= 0, height >= 0 else { return gl.setError(GL.invalidValue) }
            gl.viewport = (x, y, width, height)
        }
        t.glScissor = { x, y, width, height in
            guard let gl = KivyGL.current else { return }
            guard width >= 0, height >= 0 else { return gl.setError(GL.invalidValue) }
            gl.scissorBox = (x, y, width, height)
        }
        t.glClearColor = { r, g, b, a in KivyGL.current?.clearColor = SIMD4(r, g, b, a) }
        t.glClearStencil = { KivyGL.current?.clearStencil = $0 }
        t.glClear = { KivyGL.current?.clear($0) }
        t.glColorMask = { r, g, b, a in KivyGL.current?.colorMask = (r != 0, g != 0, b != 0, a != 0) }
        t.glBlendFunc = { source, destination in
            KivyGL.current?.blendSource = (source, source)
            KivyGL.current?.blendDestination = (destination, destination)
        }
        t.glBlendFuncSeparate = { sourceRGB, destinationRGB, sourceAlpha, destinationAlpha in
            KivyGL.current?.blendSource = (sourceRGB, sourceAlpha)
            KivyGL.current?.blendDestination = (destinationRGB, destinationAlpha)
        }
        t.glBlendEquation = { mode in KivyGL.current?.blendEquation = (mode, mode) }
        t.glBlendEquationSeparate = { rgb, alpha in KivyGL.current?.blendEquation = (rgb, alpha) }
        t.glBlendColor = { r, g, b, a in KivyGL.current?.blendColor = SIMD4(r, g, b, a) }
        t.glDepthFunc = { KivyGL.current?.depthFunc = $0 }
        t.glDepthMask = { KivyGL.current?.depthMask = $0 != 0 }
        t.glStencilFunc = { KivyGL.current?.setStencilFunc(GL.frontAndBack, $0, $1, $2) }
        t.glStencilFuncSeparate = { KivyGL.current?.setStencilFunc($0, $1, $2, $3) }
        t.glStencilOp = { KivyGL.current?.setStencilOp(GL.frontAndBack, $0, $1, $2) }
        t.glStencilOpSeparate = { KivyGL.current?.setStencilOp($0, $1, $2, $3) }
        t.glStencilMask = { KivyGL.current?.setStencilMask(GL.frontAndBack, $0) }
        t.glStencilMaskSeparate = { KivyGL.current?.setStencilMask($0, $1) }
        t.glCullFace = { KivyGL.current?.cullFaceMode = $0 }
        t.glFrontFace = { KivyGL.current?.frontFace = $0 }
        t.glLineWidth = { KivyGL.current?.lineWidth = $0 }
        t.glPolygonOffset = { _, _ in }
        t.glSampleCoverage = { _, _ in }

        // MARK: Drawing and reading
        t.glDrawArrays = { KivyGL.current?.drawArrays($0, $1, $2) }
        t.glDrawElements = { KivyGL.current?.drawElements($0, $1, $2, $3) }
        t.glReadPixels = { KivyGL.current?.readPixels($0, $1, $2, $3, $4, $5, $6) }

        return t
    }

    private static func vertexAttribValue(_ attribute: GLVertexAttribute, _ pname: GLenum) -> GLint? {
        switch pname {
        case GL.vertexAttribArrayEnabled: attribute.enabled ? 1 : 0
        case GL.vertexAttribArraySize: attribute.size
        case GL.vertexAttribArrayStride: attribute.stride
        case GL.vertexAttribArrayType: GLint(attribute.type)
        case GL.vertexAttribArrayNormalized: attribute.normalized ? 1 : 0
        case GL.vertexAttribArrayBufferBinding: GLint(attribute.buffer)
        default: nil
        }
    }
}
