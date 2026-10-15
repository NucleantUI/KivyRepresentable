cdef class NGLNUI:
    cdef bint _alive

    cpdef void create_context(self) except *
    cpdef void swap_buffers(self)
    cpdef void destroy_context(self)
