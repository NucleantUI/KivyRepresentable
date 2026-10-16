'''
NUI text provider
=================

Inside a KivyRepresentable host: the host measures text and draws it with
Skia straight into the label's texture, which Kivy's canvas then draws as any
other texture. No pixels go through Python.

Laid out as the SDL2 provider lays text out: each `_render_text` run's line
box starts at its (x, y), an outline grows it by its width on every side.
'''

__all__ = ('LabelNUI', )

from kivy.core.text import LabelBase
from kivy.core.image import ImageData
from kivy.lib import kivy_nui

_HINTING = {None: 0, 'light': 1, 'normal': 2, 'mono': 3}


def _rgba(color):
    color = list(color) + [1.0] * (4 - len(color))
    return color[:4]


class LabelNUI(LabelBase):

    _nui_fonts = {}

    def _get_font_id(self):
        return '|'.join([str(self.options[x]) for x
            in ('font_size', 'font_name_r', 'bold', 'italic', 'underline',
                'strikethrough', 'font_hinting', 'font_blended',
                'outline_width')])

    def _font(self):
        options = self.options
        key = self._get_font_id()
        font = LabelNUI._nui_fonts.get(key)
        if font is None:
            font = LabelNUI._nui_fonts[key] = kivy_nui.Font(
                path=options['font_name_r'].encode('utf-8'),
                size=int(options['font_size']),
                hinting=_HINTING.get(options['font_hinting'], 2),
                antialias=bool(options['font_blended']),
                underline=bool(options['underline']),
                strikethrough=bool(options['strikethrough']),
                outline_width=options['outline_width'] or 0)
        return font

    def get_extents(self, text):
        return kivy_nui.text_extents(self._font(), text.encode('utf-8'))

    def get_ascent(self):
        return kivy_nui.font_metrics(self._font())[0]

    def get_descent(self):
        # Negative below the baseline, as SDL2_ttf gives it.
        return -kivy_nui.font_metrics(self._font())[1]

    def _render_begin(self):
        self._runs = []

    def _render_text(self, text, x, y):
        options = self.options
        self._runs.append(kivy_nui.TextRun(
            utf8=text.encode('utf-8'), x=x, y=y,
            color=tuple(_rgba(options['color'])),
            outline_color=tuple(_rgba(options['outline_color'])),
            font=self._font()))

    def _render_end(self):
        runs, self._runs = self._runs, None
        texture = self.texture
        if texture is not None and texture.id:
            kivy_nui.draw_text(texture.id, texture.width, texture.height, runs)
        # The text is in the texture already; a one pixel image is what
        # `_render_real` leaves alone.
        return ImageData(1, 1, 'rgba', b'\x00\x00\x00\x00')
