"""
NGL/NUI: the GL context of a KivyRepresentable host.

What EGLANGLE (egl_backend/egl_angle.pyx) is to ANGLE, this is to the host's
GLES2 on Vulkan: the window asks it for a context before Kivy's first GL
call and hands it each finished frame. The host makes the context —
framebuffer 0 is the image its shader node composites — through the shared
C api (kivy_nui.h), and the `nui` cgl backend (cgl_nui.pyx) is the GL that
draws into it.
"""

include "../../lib/kivy_nui.pxi"


cdef class NGLNUI:

    cpdef void create_context(self) except *:
        if self._alive:
            return
        if not kivy_nui_create_gl_context():
            raise Exception(
                'NGLNUI: the host could not create a GL context')
        self._alive = True

    cpdef void swap_buffers(self):
        if self._alive:
            kivy_nui_present()

    cpdef void destroy_context(self):
        if self._alive:
            kivy_nui_destroy_gl_context()
            self._alive = False
