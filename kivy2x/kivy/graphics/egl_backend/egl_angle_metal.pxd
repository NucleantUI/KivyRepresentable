from kivy.graphics.egl_backend.egl_angle cimport EGLBaseANGLE

cdef extern from "egl_angle_metal_implem.h":
    cppclass MetalANGLEGraphicsContext:
        MetalANGLEGraphicsContext(void* nativeMetalLayer)
        void swapBuffersEGL()

cdef class EGLMetalANGLE(EGLBaseANGLE):
    cdef MetalANGLEGraphicsContext* ctx
    cdef void* native_layer
    cdef void set_native_layer(self, void * native_layer) except *
    cpdef void create_context(self)
    cpdef void swap_buffers(self)
    cpdef void destroy_context(self)
