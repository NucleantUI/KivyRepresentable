# Declarations of the shared C api KivyRepresentable builds
# (dependencies/CKivyNUI/include/kivy_nui.h, kivy_nui_gl.h), for the `nui`
# window (core/window/_window_nui.pyx) and cgl backend
# (graphics/cgl_backend/cgl_nui.pyx). Included like lib/sdl2.pxi.

from libc.stdint cimport int32_t, int64_t, uint8_t, uint16_t, uint32_t

cdef extern from "kivy_nui.h" nogil:

    # The host's GLES2 table. Every member is a function pointer in C; they
    # are declared `void *` here because cgl_nui.pyx casts each one to
    # Kivy's own pointer type (cgl.pxd) as it copies it, the way
    # cgl_angle.pyx casts eglGetProcAddress's result.
    ctypedef struct KivyNUIGL:
        void *glGetString
        void *glIsBuffer
        void *glIsEnabled
        void *glIsFramebuffer
        void *glIsProgram
        void *glIsRenderbuffer
        void *glIsShader
        void *glIsTexture
        void *glCheckFramebufferStatus
        void *glGetError
        void *glGetAttribLocation
        void *glGetUniformLocation
        void *glCreateProgram
        void *glCreateShader
        void *glActiveTexture
        void *glAttachShader
        void *glBindAttribLocation
        void *glBindBuffer
        void *glBindFramebuffer
        void *glBindRenderbuffer
        void *glBindTexture
        void *glBlendColor
        void *glBlendEquation
        void *glBlendEquationSeparate
        void *glBlendFunc
        void *glBlendFuncSeparate
        void *glBufferData
        void *glBufferSubData
        void *glClear
        void *glClearColor
        void *glClearStencil
        void *glColorMask
        void *glCompileShader
        void *glCompressedTexImage2D
        void *glCompressedTexSubImage2D
        void *glCopyTexImage2D
        void *glCopyTexSubImage2D
        void *glCullFace
        void *glDeleteBuffers
        void *glDeleteFramebuffers
        void *glDeleteProgram
        void *glDeleteRenderbuffers
        void *glDeleteShader
        void *glDeleteTextures
        void *glDepthFunc
        void *glDepthMask
        void *glDetachShader
        void *glDisable
        void *glDisableVertexAttribArray
        void *glDrawArrays
        void *glDrawElements
        void *glEnable
        void *glEnableVertexAttribArray
        void *glFinish
        void *glFlush
        void *glFramebufferRenderbuffer
        void *glFramebufferTexture2D
        void *glFrontFace
        void *glGenBuffers
        void *glGenerateMipmap
        void *glGenFramebuffers
        void *glGenRenderbuffers
        void *glGenTextures
        void *glGetActiveAttrib
        void *glGetActiveUniform
        void *glGetAttachedShaders
        void *glGetBooleanv
        void *glGetBufferParameteriv
        void *glGetFloatv
        void *glGetFramebufferAttachmentParameteriv
        void *glGetIntegerv
        void *glGetProgramInfoLog
        void *glGetProgramiv
        void *glGetRenderbufferParameteriv
        void *glGetShaderInfoLog
        void *glGetShaderiv
        void *glGetShaderSource
        void *glGetTexParameterfv
        void *glGetTexParameteriv
        void *glGetUniformfv
        void *glGetUniformiv
        void *glGetVertexAttribfv
        void *glGetVertexAttribiv
        void *glHint
        void *glLineWidth
        void *glLinkProgram
        void *glPixelStorei
        void *glPolygonOffset
        void *glReadPixels
        void *glRenderbufferStorage
        void *glSampleCoverage
        void *glScissor
        void *glShaderBinary
        void *glShaderSource
        void *glStencilFunc
        void *glStencilFuncSeparate
        void *glStencilMask
        void *glStencilMaskSeparate
        void *glStencilOp
        void *glStencilOpSeparate
        void *glTexImage2D
        void *glTexParameterf
        void *glTexParameteri
        void *glTexSubImage2D
        void *glUniform1f
        void *glUniform1fv
        void *glUniform1i
        void *glUniform1iv
        void *glUniform2f
        void *glUniform2fv
        void *glUniform2i
        void *glUniform2iv
        void *glUniform3f
        void *glUniform3fv
        void *glUniform3i
        void *glUniform3iv
        void *glUniform4f
        void *glUniform4fv
        void *glUniform4i
        void *glUniform4iv
        void *glUniformMatrix4fv
        void *glUseProgram
        void *glValidateProgram
        void *glVertexAttrib1f
        void *glVertexAttrib2f
        void *glVertexAttrib3f
        void *glVertexAttrib4f
        void *glVertexAttribPointer
        void *glViewport

    ctypedef struct KivyNUIWindowMetrics:
        int32_t width
        int32_t height
        int32_t pixel_width
        int32_t pixel_height
        float density
        float dpi

    ctypedef enum KivyNUIEventType:
        KIVY_NUI_EVENT_NONE
        KIVY_NUI_EVENT_QUIT
        KIVY_NUI_EVENT_MOUSE_MOTION
        KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN
        KIVY_NUI_EVENT_MOUSE_BUTTON_UP
        KIVY_NUI_EVENT_MOUSE_WHEEL
        KIVY_NUI_EVENT_FINGER_MOTION
        KIVY_NUI_EVENT_FINGER_DOWN
        KIVY_NUI_EVENT_FINGER_UP
        KIVY_NUI_EVENT_KEY_DOWN
        KIVY_NUI_EVENT_KEY_UP
        KIVY_NUI_EVENT_TEXT_INPUT
        KIVY_NUI_EVENT_TEXT_EDIT
        KIVY_NUI_EVENT_WINDOW_EXPOSED
        KIVY_NUI_EVENT_WINDOW_RESIZED
        KIVY_NUI_EVENT_WINDOW_MINIMIZED
        KIVY_NUI_EVENT_WINDOW_MAXIMIZED
        KIVY_NUI_EVENT_WINDOW_RESTORED
        KIVY_NUI_EVENT_WINDOW_SHOWN
        KIVY_NUI_EVENT_WINDOW_HIDDEN
        KIVY_NUI_EVENT_WINDOW_ENTER
        KIVY_NUI_EVENT_WINDOW_LEAVE
        KIVY_NUI_EVENT_WINDOW_FOCUS_GAINED
        KIVY_NUI_EVENT_WINDOW_FOCUS_LOST
        KIVY_NUI_EVENT_WINDOW_CLOSE
        KIVY_NUI_EVENT_WINDOW_MOVED
        KIVY_NUI_EVENT_WINDOW_DISPLAY_CHANGED
        KIVY_NUI_EVENT_DROP_BEGIN
        KIVY_NUI_EVENT_DROP_FILE
        KIVY_NUI_EVENT_DROP_TEXT
        KIVY_NUI_EVENT_DROP_END
        KIVY_NUI_EVENT_APP_TERMINATING
        KIVY_NUI_EVENT_APP_LOW_MEMORY
        KIVY_NUI_EVENT_APP_WILL_ENTER_BACKGROUND
        KIVY_NUI_EVENT_APP_DID_ENTER_BACKGROUND
        KIVY_NUI_EVENT_APP_WILL_ENTER_FOREGROUND
        KIVY_NUI_EVENT_APP_DID_ENTER_FOREGROUND

    int KIVY_NUI_TEXT_SIZE

    ctypedef struct KivyNUIMouseEvent:
        int32_t x, y
        uint8_t button
    ctypedef struct KivyNUIWheelEvent:
        int32_t x, y, mouse_x, mouse_y
    ctypedef struct KivyNUIFingerEvent:
        int64_t finger_id
        float x, y, pressure
    ctypedef struct KivyNUIKeyEvent:
        int32_t keycode, scancode
        uint16_t mod
    ctypedef struct KivyNUITextEvent:
        char utf8[32]
    ctypedef struct KivyNUIWindowEvent:
        int32_t data1, data2
    ctypedef struct KivyNUIDropEvent:
        const char *utf8
        int32_t x, y

    # The union is anonymous in C; its members are reached directly.
    ctypedef struct KivyNUIEvent:
        KivyNUIEventType type
        KivyNUIMouseEvent mouse
        KivyNUIWheelEvent wheel
        KivyNUIFingerEvent finger
        KivyNUIKeyEvent key
        KivyNUITextEvent text
        KivyNUIWindowEvent window
        KivyNUIDropEvent drop

    ctypedef enum KivyNUICursor:
        KIVY_NUI_CURSOR_ARROW
        KIVY_NUI_CURSOR_IBEAM
        KIVY_NUI_CURSOR_WAIT
        KIVY_NUI_CURSOR_CROSSHAIR
        KIVY_NUI_CURSOR_WAIT_ARROW
        KIVY_NUI_CURSOR_SIZE_NWSE
        KIVY_NUI_CURSOR_SIZE_NESW
        KIVY_NUI_CURSOR_SIZE_WE
        KIVY_NUI_CURSOR_SIZE_NS
        KIVY_NUI_CURSOR_SIZE_ALL
        KIVY_NUI_CURSOR_NO
        KIVY_NUI_CURSOR_HAND

    ctypedef struct KivyNUIKivy:
        void *context
        void (*tick)(void *context, double dt) noexcept with gil

    bint kivy_nui_is_hosted()
    void kivy_nui_set_kivy(const KivyNUIKivy *kivy)

    const KivyNUIGL *kivy_nui_gl()
    bint kivy_nui_create_gl_context()
    void kivy_nui_destroy_gl_context()
    void kivy_nui_present()

    void kivy_nui_get_window_metrics(KivyNUIWindowMetrics *out)
    void kivy_nui_set_title(const char *utf8)
    void kivy_nui_set_system_cursor(KivyNUICursor cursor)
    void kivy_nui_set_cursor_visible(bint visible)
    void kivy_nui_show_keyboard()
    void kivy_nui_hide_keyboard()
    void kivy_nui_request_close()

    bint kivy_nui_poll_event(KivyNUIEvent *out)

    # Text and images, for the `nui` text and image providers (lib/_kivy_nui.pyx).
    ctypedef struct KivyNUIFont:
        const char *path
        float size
        int32_t hinting
        bint antialias
        bint underline
        bint strikethrough
        float outline_width

    ctypedef struct KivyNUITextRun:
        const char *utf8
        float x
        float y
        float color[4]
        float outline_color[4]
        KivyNUIFont font

    bint kivy_nui_has_text_and_images()
    bint kivy_nui_text_extents(const KivyNUIFont *font, const char *utf8, int32_t *width, int32_t *height)
    bint kivy_nui_font_metrics(const KivyNUIFont *font, int32_t *ascent, int32_t *descent)
    bint kivy_nui_draw_text(uint32_t texture, int32_t width, int32_t height, const KivyNUITextRun *runs, int32_t count)
    bint kivy_nui_image_size(const void *data, size_t size, int32_t *width, int32_t *height)
    bint kivy_nui_draw_image(uint32_t texture, int32_t width, int32_t height, const void *data, size_t size)
    bint kivy_nui_image_pixels(const void *data, size_t size, uint8_t *out, size_t out_size)
