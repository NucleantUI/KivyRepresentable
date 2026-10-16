'''
NUI image loader
================

Inside a KivyRepresentable host: the host decodes the image with Skia (an
SVG with Skia's SVG module, at its own width and height, or its viewBox's)
and draws it straight into the texture's image when Kivy first binds it,
and again whenever the graphics context reloads (which recreates every
texture empty); Kivy's canvas then draws the texture as any other. Only the
file's bytes go through Python, never the decoded pixels.

With `keep_data` (pixels Kivy reads back, as `read_pixel` does) the host
decodes into bytes and Kivy uploads them as it does with other loaders.
'''

__all__ = ('ImageLoaderNUI', )

from kivy.cache import Cache
from kivy.core.image import ImageData, ImageLoader, ImageLoaderBase
from kivy.lib import kivy_nui


class ImageLoaderNUI(ImageLoaderBase):

    @staticmethod
    def extensions():
        # Skia's decoders and its SVG module. GIF stays with the loaders that
        # read every frame.
        return ('png', 'jpg', 'jpeg', 'jpe', 'webp', 'bmp', 'ico', 'wbmp',
                'svg')

    @staticmethod
    def can_load_memory():
        return True

    def load(self, filename):
        if self._inline:
            filename.seek(0)
            data = filename.read()
            source = None
        else:
            with open(filename, 'rb') as f:
                data = f.read()
            source = filename
        size = kivy_nui.image_size(data)
        if size is None:
            raise Exception('Image: unable to load {}'.format(filename))
        width, height = size
        if self.keep_data:
            pixels = kivy_nui.image_pixels(data, width, height)
            if pixels is None:
                raise Exception('Image: unable to decode {}'.format(filename))
            return [ImageData(width, height, 'rgba', pixels, source=source)]
        self._encoded = data
        return [ImageData(width, height, 'rgba', None, source=source)]

    def populate(self):
        if self.keep_data:
            return super().populate()
        from kivy.graphics.texture import Texture
        self._textures = []
        fname = self.filename
        uid = f'{fname}|{self._mipmap:d}|0'
        texture = Cache.get('kv.texture', uid)
        if texture is None:
            imagedata = self._data[0]
            source = (f"{'zip|' if fname.endswith('.zip') else ''}"
                      f"{self._nocache}|")
            imagedata.source = f'{source}{uid}'
            # Filled when Kivy first binds it, and after a reload, as a
            # label's texture is.
            fill = _filler(self._encoded)
            texture = Texture.create(
                size=(imagedata.width, imagedata.height), colorfmt='rgba',
                mipmap=self._mipmap, callback=fill)
            texture.add_reload_observer(fill)
            if not self._nocache:
                Cache.append('kv.texture', uid, texture)
            if imagedata.flip_vertical:
                texture.flip_vertical()
        self._encoded = None
        self._textures.append(texture)


def _filler(data):
    '''Draws the encoded image `data` into a texture. A plain function, so
    the texture's reload observers hold it (and `data`) for as long as the
    texture lives; a loader's bound method they would hold weakly.'''
    def fill(texture):
        kivy_nui.draw_image(texture.id, texture.width, texture.height, data)
    return fill


# register
ImageLoader.register(ImageLoaderNUI)
