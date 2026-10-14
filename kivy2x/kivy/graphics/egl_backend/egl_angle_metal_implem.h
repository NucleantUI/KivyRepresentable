#include <Metal/Metal.h>
#include <QuartzCore/CAMetalLayer.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

class MetalANGLEGraphicsContext
{
public:
    MetalANGLEGraphicsContext(void *nativeMetalLayer);
    ~MetalANGLEGraphicsContext();
    void swapBuffersEGL();
private:
    void* m_nativeMetalLayer;
    EGLDisplay m_displayObj;
    EGLSurface m_surfaceObj;
    EGLContext m_contextObj;
    EGLConfig m_configObj;
    void initialiseEGLDisplay();
    void initialiseEGLContext();
};
