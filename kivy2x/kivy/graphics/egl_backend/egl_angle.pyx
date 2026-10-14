include "../../include/config.pxi"


cdef class EGLBaseANGLE:
    cdef void set_native_layer(self, void * native_layer) except *:
        pass

    cpdef void create_context(self):
        pass

    cpdef void swap_buffers(self):
        pass

    cpdef void destroy_context(self):
        pass


cdef class EGLANGLE:
    """Proxy class that dispatches to platform-specific EGL implementation.
    On iOS/macOS: uses EGLMetalANGLE (Metal-backed ANGLE EGL).
    Elsewhere: EGLBaseANGLE (no-op).
    """

    def __cinit__(self):
        self._initialize_angle_implementation()

    cdef void _initialize_angle_implementation(self):
        IF PLATFORM in ('ios', 'darwin'):
            from kivy.graphics.egl_backend.egl_angle_metal import EGLMetalANGLE
            self._egl = EGLMetalANGLE()
        ELSE:
            self._egl = EGLBaseANGLE()

    cdef void set_native_layer(self, void * native_layer) except *:
        self._egl.set_native_layer(native_layer)

    cpdef void create_context(self):
        self._egl.create_context()

    cpdef void swap_buffers(self):
        self._egl.swap_buffers()

    cpdef void destroy_context(self):
        self._egl.destroy_context()
