"""
CGL/NUI: GL backend implementation on KivyRepresentable's GLES2 table.

The host (a Swift app built on KivyRepresentable) implements Kivy's GLES2
functions on Vulkan, rendering into the image its shader node draws, and
registers them with the shared C api (kivy_nui.h) before Python starts. This
backend copies that table into Kivy's, the way cgl_angle fills it from
eglGetProcAddress. Selected with ``KIVY_GL_BACKEND=nui``.
"""

include "../common.pxi"
include "../../include/config.pxi"
include "../../lib/kivy_nui.pxi"

from kivy.graphics.cgl cimport *


cpdef is_backend_supported():
    return kivy_nui_is_hosted()


def init_backend():
    cdef const KivyNUIGL *gl = kivy_nui_gl()
    if gl == NULL:
        raise TypeError(
            'NUI GL backend is not available: no host has registered with '
            'kivy_nui_set_host. It only runs inside a KivyRepresentable app.')
    cgl.glActiveTexture = <GLACTIVETEXTUREPTR>gl.glActiveTexture
    cgl.glAttachShader = <GLATTACHSHADERPTR>gl.glAttachShader
    cgl.glBindAttribLocation = <GLBINDATTRIBLOCATIONPTR>gl.glBindAttribLocation
    cgl.glBindBuffer = <GLBINDBUFFERPTR>gl.glBindBuffer
    cgl.glBindFramebuffer = <GLBINDFRAMEBUFFERPTR>gl.glBindFramebuffer
    cgl.glBindRenderbuffer = <GLBINDRENDERBUFFERPTR>gl.glBindRenderbuffer
    cgl.glBindTexture = <GLBINDTEXTUREPTR>gl.glBindTexture
    cgl.glBlendColor = <GLBLENDCOLORPTR>gl.glBlendColor
    cgl.glBlendEquation = <GLBLENDEQUATIONPTR>gl.glBlendEquation
    cgl.glBlendEquationSeparate = <GLBLENDEQUATIONSEPARATEPTR>gl.glBlendEquationSeparate
    cgl.glBlendFunc = <GLBLENDFUNCPTR>gl.glBlendFunc
    cgl.glBlendFuncSeparate = <GLBLENDFUNCSEPARATEPTR>gl.glBlendFuncSeparate
    cgl.glBufferData = <GLBUFFERDATAPTR>gl.glBufferData
    cgl.glBufferSubData = <GLBUFFERSUBDATAPTR>gl.glBufferSubData
    cgl.glCheckFramebufferStatus = <GLCHECKFRAMEBUFFERSTATUSPTR>gl.glCheckFramebufferStatus
    cgl.glClear = <GLCLEARPTR>gl.glClear
    cgl.glClearColor = <GLCLEARCOLORPTR>gl.glClearColor
    cgl.glClearStencil = <GLCLEARSTENCILPTR>gl.glClearStencil
    cgl.glColorMask = <GLCOLORMASKPTR>gl.glColorMask
    cgl.glCompileShader = <GLCOMPILESHADERPTR>gl.glCompileShader
    cgl.glCompressedTexImage2D = <GLCOMPRESSEDTEXIMAGE2DPTR>gl.glCompressedTexImage2D
    cgl.glCompressedTexSubImage2D = <GLCOMPRESSEDTEXSUBIMAGE2DPTR>gl.glCompressedTexSubImage2D
    cgl.glCopyTexImage2D = <GLCOPYTEXIMAGE2DPTR>gl.glCopyTexImage2D
    cgl.glCopyTexSubImage2D = <GLCOPYTEXSUBIMAGE2DPTR>gl.glCopyTexSubImage2D
    cgl.glCreateProgram = <GLCREATEPROGRAMPTR>gl.glCreateProgram
    cgl.glCreateShader = <GLCREATESHADERPTR>gl.glCreateShader
    cgl.glCullFace = <GLCULLFACEPTR>gl.glCullFace
    cgl.glDeleteBuffers = <GLDELETEBUFFERSPTR>gl.glDeleteBuffers
    cgl.glDeleteFramebuffers = <GLDELETEFRAMEBUFFERSPTR>gl.glDeleteFramebuffers
    cgl.glDeleteProgram = <GLDELETEPROGRAMPTR>gl.glDeleteProgram
    cgl.glDeleteRenderbuffers = <GLDELETERENDERBUFFERSPTR>gl.glDeleteRenderbuffers
    cgl.glDeleteShader = <GLDELETESHADERPTR>gl.glDeleteShader
    cgl.glDeleteTextures = <GLDELETETEXTURESPTR>gl.glDeleteTextures
    cgl.glDepthFunc = <GLDEPTHFUNCPTR>gl.glDepthFunc
    cgl.glDepthMask = <GLDEPTHMASKPTR>gl.glDepthMask
    cgl.glDetachShader = <GLDETACHSHADERPTR>gl.glDetachShader
    cgl.glDisable = <GLDISABLEPTR>gl.glDisable
    cgl.glDisableVertexAttribArray = <GLDISABLEVERTEXATTRIBARRAYPTR>gl.glDisableVertexAttribArray
    cgl.glDrawArrays = <GLDRAWARRAYSPTR>gl.glDrawArrays
    cgl.glDrawElements = <GLDRAWELEMENTSPTR>gl.glDrawElements
    cgl.glEnable = <GLENABLEPTR>gl.glEnable
    cgl.glEnableVertexAttribArray = <GLENABLEVERTEXATTRIBARRAYPTR>gl.glEnableVertexAttribArray
    cgl.glFinish = <GLFINISHPTR>gl.glFinish
    cgl.glFlush = <GLFLUSHPTR>gl.glFlush
    cgl.glFramebufferRenderbuffer = <GLFRAMEBUFFERRENDERBUFFERPTR>gl.glFramebufferRenderbuffer
    cgl.glFramebufferTexture2D = <GLFRAMEBUFFERTEXTURE2DPTR>gl.glFramebufferTexture2D
    cgl.glFrontFace = <GLFRONTFACEPTR>gl.glFrontFace
    cgl.glGenBuffers = <GLGENBUFFERSPTR>gl.glGenBuffers
    cgl.glGenerateMipmap = <GLGENERATEMIPMAPPTR>gl.glGenerateMipmap
    cgl.glGenFramebuffers = <GLGENFRAMEBUFFERSPTR>gl.glGenFramebuffers
    cgl.glGenRenderbuffers = <GLGENRENDERBUFFERSPTR>gl.glGenRenderbuffers
    cgl.glGenTextures = <GLGENTEXTURESPTR>gl.glGenTextures
    cgl.glGetActiveAttrib = <GLGETACTIVEATTRIBPTR>gl.glGetActiveAttrib
    cgl.glGetActiveUniform = <GLGETACTIVEUNIFORMPTR>gl.glGetActiveUniform
    cgl.glGetAttachedShaders = <GLGETATTACHEDSHADERSPTR>gl.glGetAttachedShaders
    cgl.glGetAttribLocation = <GLGETATTRIBLOCATIONPTR>gl.glGetAttribLocation
    cgl.glGetBooleanv = <GLGETBOOLEANVPTR>gl.glGetBooleanv
    cgl.glGetBufferParameteriv = <GLGETBUFFERPARAMETERIVPTR>gl.glGetBufferParameteriv
    cgl.glGetError = <GLGETERRORPTR>gl.glGetError
    cgl.glGetFloatv = <GLGETFLOATVPTR>gl.glGetFloatv
    cgl.glGetFramebufferAttachmentParameteriv = <GLGETFRAMEBUFFERATTACHMENTPARAMETERIVPTR>gl.glGetFramebufferAttachmentParameteriv
    cgl.glGetIntegerv = <GLGETINTEGERVPTR>gl.glGetIntegerv
    cgl.glGetProgramInfoLog = <GLGETPROGRAMINFOLOGPTR>gl.glGetProgramInfoLog
    cgl.glGetProgramiv = <GLGETPROGRAMIVPTR>gl.glGetProgramiv
    cgl.glGetRenderbufferParameteriv = <GLGETRENDERBUFFERPARAMETERIVPTR>gl.glGetRenderbufferParameteriv
    cgl.glGetShaderInfoLog = <GLGETSHADERINFOLOGPTR>gl.glGetShaderInfoLog
    cgl.glGetShaderiv = <GLGETSHADERIVPTR>gl.glGetShaderiv
    cgl.glGetShaderSource = <GLGETSHADERSOURCEPTR>gl.glGetShaderSource
    cgl.glGetString = <GLGETSTRINGPTR>gl.glGetString
    cgl.glGetTexParameterfv = <GLGETTEXPARAMETERFVPTR>gl.glGetTexParameterfv
    cgl.glGetTexParameteriv = <GLGETTEXPARAMETERIVPTR>gl.glGetTexParameteriv
    cgl.glGetUniformfv = <GLGETUNIFORMFVPTR>gl.glGetUniformfv
    cgl.glGetUniformiv = <GLGETUNIFORMIVPTR>gl.glGetUniformiv
    cgl.glGetUniformLocation = <GLGETUNIFORMLOCATIONPTR>gl.glGetUniformLocation
    cgl.glGetVertexAttribfv = <GLGETVERTEXATTRIBFVPTR>gl.glGetVertexAttribfv
    cgl.glGetVertexAttribiv = <GLGETVERTEXATTRIBIVPTR>gl.glGetVertexAttribiv
    cgl.glHint = <GLHINTPTR>gl.glHint
    cgl.glIsBuffer = <GLISBUFFERPTR>gl.glIsBuffer
    cgl.glIsEnabled = <GLISENABLEDPTR>gl.glIsEnabled
    cgl.glIsFramebuffer = <GLISFRAMEBUFFERPTR>gl.glIsFramebuffer
    cgl.glIsProgram = <GLISPROGRAMPTR>gl.glIsProgram
    cgl.glIsRenderbuffer = <GLISRENDERBUFFERPTR>gl.glIsRenderbuffer
    cgl.glIsShader = <GLISSHADERPTR>gl.glIsShader
    cgl.glIsTexture = <GLISTEXTUREPTR>gl.glIsTexture
    cgl.glLineWidth = <GLLINEWIDTHPTR>gl.glLineWidth
    cgl.glLinkProgram = <GLLINKPROGRAMPTR>gl.glLinkProgram
    cgl.glPixelStorei = <GLPIXELSTOREIPTR>gl.glPixelStorei
    cgl.glPolygonOffset = <GLPOLYGONOFFSETPTR>gl.glPolygonOffset
    cgl.glReadPixels = <GLREADPIXELSPTR>gl.glReadPixels
    cgl.glRenderbufferStorage = <GLRENDERBUFFERSTORAGEPTR>gl.glRenderbufferStorage
    cgl.glSampleCoverage = <GLSAMPLECOVERAGEPTR>gl.glSampleCoverage
    cgl.glScissor = <GLSCISSORPTR>gl.glScissor
    cgl.glShaderBinary = <GLSHADERBINARYPTR>gl.glShaderBinary
    cgl.glShaderSource = <GLSHADERSOURCEPTR>gl.glShaderSource
    cgl.glStencilFunc = <GLSTENCILFUNCPTR>gl.glStencilFunc
    cgl.glStencilFuncSeparate = <GLSTENCILFUNCSEPARATEPTR>gl.glStencilFuncSeparate
    cgl.glStencilMask = <GLSTENCILMASKPTR>gl.glStencilMask
    cgl.glStencilMaskSeparate = <GLSTENCILMASKSEPARATEPTR>gl.glStencilMaskSeparate
    cgl.glStencilOp = <GLSTENCILOPPTR>gl.glStencilOp
    cgl.glStencilOpSeparate = <GLSTENCILOPSEPARATEPTR>gl.glStencilOpSeparate
    cgl.glTexImage2D = <GLTEXIMAGE2DPTR>gl.glTexImage2D
    cgl.glTexParameterf = <GLTEXPARAMETERFPTR>gl.glTexParameterf
    cgl.glTexParameteri = <GLTEXPARAMETERIPTR>gl.glTexParameteri
    cgl.glTexSubImage2D = <GLTEXSUBIMAGE2DPTR>gl.glTexSubImage2D
    cgl.glUniform1f = <GLUNIFORM1FPTR>gl.glUniform1f
    cgl.glUniform1fv = <GLUNIFORM1FVPTR>gl.glUniform1fv
    cgl.glUniform1i = <GLUNIFORM1IPTR>gl.glUniform1i
    cgl.glUniform1iv = <GLUNIFORM1IVPTR>gl.glUniform1iv
    cgl.glUniform2f = <GLUNIFORM2FPTR>gl.glUniform2f
    cgl.glUniform2fv = <GLUNIFORM2FVPTR>gl.glUniform2fv
    cgl.glUniform2i = <GLUNIFORM2IPTR>gl.glUniform2i
    cgl.glUniform2iv = <GLUNIFORM2IVPTR>gl.glUniform2iv
    cgl.glUniform3f = <GLUNIFORM3FPTR>gl.glUniform3f
    cgl.glUniform3fv = <GLUNIFORM3FVPTR>gl.glUniform3fv
    cgl.glUniform3i = <GLUNIFORM3IPTR>gl.glUniform3i
    cgl.glUniform3iv = <GLUNIFORM3IVPTR>gl.glUniform3iv
    cgl.glUniform4f = <GLUNIFORM4FPTR>gl.glUniform4f
    cgl.glUniform4fv = <GLUNIFORM4FVPTR>gl.glUniform4fv
    cgl.glUniform4i = <GLUNIFORM4IPTR>gl.glUniform4i
    cgl.glUniform4iv = <GLUNIFORM4IVPTR>gl.glUniform4iv
    cgl.glUniformMatrix4fv = <GLUNIFORMMATRIX4FVPTR>gl.glUniformMatrix4fv
    cgl.glUseProgram = <GLUSEPROGRAMPTR>gl.glUseProgram
    cgl.glValidateProgram = <GLVALIDATEPROGRAMPTR>gl.glValidateProgram
    cgl.glVertexAttrib1f = <GLVERTEXATTRIB1FPTR>gl.glVertexAttrib1f
    cgl.glVertexAttrib2f = <GLVERTEXATTRIB2FPTR>gl.glVertexAttrib2f
    cgl.glVertexAttrib3f = <GLVERTEXATTRIB3FPTR>gl.glVertexAttrib3f
    cgl.glVertexAttrib4f = <GLVERTEXATTRIB4FPTR>gl.glVertexAttrib4f
    cgl.glVertexAttribPointer = <GLVERTEXATTRIBPOINTERPTR>gl.glVertexAttribPointer
    cgl.glViewport = <GLVIEWPORTPTR>gl.glViewport
