cdef class EGLBaseANGLE:
    cdef void set_native_layer(self, void * native_layer) except *
    cpdef void create_context(self)
    cpdef void swap_buffers(self)
    cpdef void destroy_context(self)

cdef class EGLANGLE:
    cdef EGLBaseANGLE _egl
    cdef void _initialize_angle_implementation(self)
    cdef void set_native_layer(self, void * native_layer) except *
    cpdef void create_context(self)
    cpdef void swap_buffers(self)
    cpdef void destroy_context(self)
