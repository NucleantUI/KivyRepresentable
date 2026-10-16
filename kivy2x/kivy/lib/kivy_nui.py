'''
KivyRepresentable's text and image calls (`kivy_nui.h`), for the `nui` text
and image providers: the host measures text, decodes images, and draws both
with Skia straight into a texture's image.

The calls are compiled (lib/_kivy_nui.pyx) against the shared C api Kivy's
nui extensions link, so they reach the library the host registered with.
Importing this module raises ImportError when Kivy was built without
USE_NUI, outside a host, or with one that doesn't draw text and images, so
the providers fall through to the next one.
'''

__all__ = ('Font', 'TextRun', 'text_extents', 'font_metrics', 'draw_text',
           'image_size', 'draw_image', 'image_pixels')

try:
    from kivy.lib._kivy_nui import (
        Font, TextRun, has_text_and_images, text_extents, font_metrics,
        draw_text, image_size, draw_image, image_pixels)
except ImportError as error:
    raise ImportError('kivy_nui: Kivy was built without USE_NUI') from error

if not has_text_and_images():
    raise ImportError('kivy_nui: no host drawing text and images')
