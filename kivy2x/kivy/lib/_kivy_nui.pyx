'''
KivyRepresentable's text and image calls (`kivy_nui.h`), for the `nui` text
and image providers through `kivy.lib.kivy_nui`: the host measures text,
decodes images, and draws both with Skia straight into a texture's image.

Compiled against the shared C api like Kivy's other nui modules, so a call
is a plain C call into the library the host registered with — in the
browser, into the app itself, with nothing between them that would keep
the host from waiting on the GPU.
'''

include "kivy_nui.pxi"

from libc.stdlib cimport malloc, free
from libc.string cimport memset

__all__ = ('Font', 'TextRun', 'has_text_and_images', 'text_extents',
           'font_metrics', 'draw_text', 'image_size', 'draw_image',
           'image_pixels')


class Font:
    '''A font as the providers use it: its file and the label options that
    change how it is measured and drawn (KivyNUIFont).'''

    __slots__ = ('path', 'size', 'hinting', 'antialias', 'underline',
                 'strikethrough', 'outline_width')

    def __init__(self, path=b'', size=0, hinting=2, antialias=True,
                 underline=False, strikethrough=False, outline_width=0):
        self.path = path
        self.size = size
        self.hinting = hinting
        self.antialias = antialias
        self.underline = underline
        self.strikethrough = strikethrough
        self.outline_width = outline_width


class TextRun:
    '''One `_render_text` call (KivyNUITextRun).'''

    __slots__ = ('utf8', 'x', 'y', 'color', 'outline_color', 'font')

    def __init__(self, utf8=b'', x=0, y=0, color=(1, 1, 1, 1),
                 outline_color=(0, 0, 0, 1), font=None):
        self.utf8 = utf8
        self.x = x
        self.y = y
        self.color = color
        self.outline_color = outline_color
        self.font = font


cdef void fill_font(KivyNUIFont *out, font, bytes path):
    # `path` is font.path, held by the caller for the duration of the call.
    out.path = path
    out.size = font.size
    out.hinting = font.hinting
    out.antialias = font.antialias
    out.underline = font.underline
    out.strikethrough = font.strikethrough
    out.outline_width = font.outline_width


def has_text_and_images():
    '''Whether a host that draws text and images is registered.'''
    return bool(kivy_nui_has_text_and_images())


def text_extents(font, bytes utf8):
    '''(width, height) of `utf8` (bytes) in `font`, (0, 0) when the host
    can't measure it.'''
    cdef KivyNUIFont f
    cdef int32_t width = 0, height = 0
    cdef bytes path = font.path
    fill_font(&f, font, path)
    if not kivy_nui_text_extents(&f, utf8, &width, &height):
        return 0, 0
    return width, height


def font_metrics(font):
    '''(ascent, descent) in pixels, both positive.'''
    cdef KivyNUIFont f
    cdef int32_t ascent = 0, descent = 0
    cdef bytes path = font.path
    fill_font(&f, font, path)
    if not kivy_nui_font_metrics(&f, &ascent, &descent):
        return 0, 0
    return ascent, descent


def draw_text(uint32_t texture, int32_t width, int32_t height, runs):
    '''Clears GL texture `texture` and draws `runs` (TextRun) into it.'''
    cdef int32_t count = len(runs)
    cdef KivyNUITextRun *array = <KivyNUITextRun *>malloc(max(count, 1) * sizeof(KivyNUITextRun))
    if array == NULL:
        raise MemoryError()
    # The C strings point into these until the call returns.
    keep = []
    cdef int i, k
    try:
        memset(array, 0, max(count, 1) * sizeof(KivyNUITextRun))
        for i, run in enumerate(runs):
            utf8 = run.utf8
            path = run.font.path
            keep.append((utf8, path))
            array[i].utf8 = <bytes>utf8
            array[i].x = run.x
            array[i].y = run.y
            for k in range(4):
                array[i].color[k] = run.color[k]
                array[i].outline_color[k] = run.outline_color[k]
            fill_font(&array[i].font, run.font, <bytes>path)
        return bool(kivy_nui_draw_text(texture, width, height, array, count))
    finally:
        free(array)


def image_size(bytes data):
    '''(width, height) of the encoded image `data` (bytes), or None.'''
    cdef int32_t width = 0, height = 0
    cdef const char *bytes_ = data
    if not kivy_nui_image_size(bytes_, len(data), &width, &height):
        return None
    return width, height


def draw_image(uint32_t texture, int32_t width, int32_t height, bytes data):
    '''Decodes `data` and draws it at the top-left of GL texture `texture`.'''
    cdef const char *bytes_ = data
    return bool(kivy_nui_draw_image(texture, width, height, bytes_, len(data)))


def image_pixels(bytes data, int width, int height):
    '''The decoded image as RGBA bytes, first row first, or None.'''
    out = bytearray(width * height * 4)
    cdef unsigned char[:] view = out
    cdef const char *bytes_ = data
    if not kivy_nui_image_pixels(bytes_, len(data), &view[0], len(out)):
        return None
    return bytes(out)
