# distutils: language = c++
from kivy.graphics.egl_backend.egl_angle_metal cimport MetalANGLEGraphicsContext, EGLMetalANGLE

cdef class EGLMetalANGLE:

    cdef void set_native_layer(self, void * native_layer) except *:
        self.native_layer = native_layer

    cpdef void create_context(self):
        self.ctx = new MetalANGLEGraphicsContext(self.native_layer)

    cpdef void swap_buffers(self):
        self.ctx.swapBuffersEGL()

    cpdef void destroy_context(self):
        del self.ctx
