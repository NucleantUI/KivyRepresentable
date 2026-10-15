'''
Kivy rendering through KivyRepresentable's GL — its GLES2 on Vulkan — with
no window: a headless host (libKivyNUIHeadless) is registered before Kivy is
imported, Kivy's `nui` window asks it for a GL context (ngl_nui), the app is
ticked a few frames, and framebuffer 0 is read back and checked. Each test
runs in its own Python process, because Kivy's window and GL backend are
chosen once per process. Every test also saves its last frame as a PNG
(`KIVY_NUI_SHOTS`, default the system temp dir).

Needs `swift build --product CKivyNUI`, `swift build --product
KivyNUIHeadless`, and kivy2x built with USE_NUI=1, run with that build's
Python (Pillow for the text provider; see kivy-notes.md). From the package
root:

    python Tests/kivy/test_render_nui.py
'''

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# KIVY_NUI_INSTALLED=1: test the Kivy installed in this Python (the wheel)
# instead of the kivy2x checkout.
KIVY = None if os.environ.get('KIVY_NUI_INSTALLED') else os.path.join(ROOT, 'kivy2x')
LIB = os.path.join(ROOT, '.build', 'debug', 'libCKivyNUI.dylib')
HEADLESS = os.path.join(ROOT, '.build', 'debug', 'libKivyNUIHeadless.dylib')
SHOTS = os.environ.get('KIVY_NUI_SHOTS', tempfile.gettempdir())
WIDTH, HEIGHT = 320, 240


HOST = r'''
import ctypes, os, sys
if KIVY:
    sys.path.insert(0, KIVY)
nui = ctypes.CDLL(LIB, mode=ctypes.RTLD_GLOBAL)
nui.kivy_nui_tick.argtypes = [ctypes.c_double]
headless = ctypes.CDLL(HEADLESS)
headless.kivy_nui_headless_start.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32, ctypes.c_float]
headless.kivy_nui_headless_start.restype = ctypes.c_bool
headless.kivy_nui_headless_read.argtypes = [ctypes.c_void_p]
headless.kivy_nui_headless_read.restype = ctypes.c_bool
assert headless.kivy_nui_headless_start(LIB.encode(), WIDTH, HEIGHT, 1.0)

os.environ['KIVY_WINDOW'] = 'nui'
os.environ['KIVY_GL_BACKEND'] = 'nui'
os.environ['KIVY_NO_ARGS'] = '1'
os.environ['KIVY_NO_CONFIG'] = '1'
os.environ['KIVY_NO_FILELOG'] = '1'

def tick(n=1):
    for _ in range(n):
        nui.kivy_nui_tick(1 / 60.)

def frame():
    """(width, height, rgba bytes), bottom row first, as glReadPixels."""
    pixels = (ctypes.c_uint8 * (WIDTH * HEIGHT * 4))()
    assert headless.kivy_nui_headless_read(pixels), 'no GL context'
    return bytes(pixels)

def pixel(data, x, y):
    """Kivy's coordinates: from the bottom-left."""
    i = (y * WIDTH + x) * 4
    return tuple(data[i:i + 4])

def save(data, name):
    from PIL import Image
    image = Image.frombytes('RGBA', (WIDTH, HEIGHT), data)
    image.transpose(Image.FLIP_TOP_BOTTOM).save(os.path.join(SHOTS, name + '.png'))

def near(a, b, tolerance=3):
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))
'''


CANVAS_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Rectangle, Ellipse, Line, Mesh

class Shapes(App):
    def build(self):
        root = Widget()
        with root.canvas:
            Color(1, 0, 0, 1)
            Rectangle(pos=(0, 0), size=(160, 120))
            Color(0, 0, 1, 1)
            Rectangle(pos=(160, 120), size=(160, 120))
            Color(0, 1, 0, 1)
            Ellipse(pos=(200, 10), size=(100, 100))
            Color(1, 1, 0, 1)
            Line(points=[10, 200, 150, 200], width=1)
            Color(1, 0, 1, 1)
            Mesh(vertices=[20, 140, 0, 0, 60, 140, 0, 0, 60, 180, 0, 0, 20, 180, 0, 0],
                 indices=[0, 1, 2, 3], mode='triangle_fan')
        return root

Shapes().run()
tick(4)
data = frame()
save(data, 'nui_canvas')
assert pixel(data, 40, 30) == (255, 0, 0, 255), pixel(data, 40, 30)
assert pixel(data, 240, 180) == (0, 0, 255, 255), pixel(data, 240, 180)
assert pixel(data, 250, 60) == (0, 255, 0, 255), pixel(data, 250, 60)   # ellipse middle
assert pixel(data, 205, 15) != (0, 255, 0, 255), pixel(data, 205, 15)   # outside its curve
assert pixel(data, 40, 160) == (255, 0, 255, 255), pixel(data, 40, 160) # fan
line = [pixel(data, 80, y) for y in range(198, 203)]
assert (255, 255, 0, 255) in line, line
assert pixel(data, 100, 220)[:3] == (0, 0, 0), pixel(data, 100, 220)    # Window.clearcolor
print('OK')
'''


WIDGETS_TEST = r'''
from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label

class Widgets(App):
    def build(self):
        root = BoxLayout(orientation='vertical', padding=10, spacing=10)
        root.add_widget(Label(text='KivyRepresentable', font_size=28))
        root.add_widget(Button(text='Vulkan'))
        return root

Widgets().run()
tick(6)
data = frame()
save(data, 'nui_widgets')
# The Button's background image (a texture atlas) is grey; its text white.
button = [pixel(data, x, 60) for x in range(20, 300, 7)]
assert any(near(p, (88, 88, 88, 255), 40) for p in button), button
label_rows = [pixel(data, x, y) for x in range(40, 280, 2) for y in range(160, 200, 2)]
assert any(p[0] > 200 for p in label_rows), 'no text drawn in the label'
print('OK')
'''


STENCIL_FBO_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.uix.stencilview import StencilView
from kivy.graphics import Color, Rectangle, Fbo, ClearColor, ClearBuffers

class Clipped(App):
    def build(self):
        root = Widget()
        clip = StencilView(pos=(0, 0), size=(100, 100))
        with clip.canvas:
            Color(0, 1, 0, 1)
            Rectangle(pos=(0, 0), size=(300, 300))
        root.add_widget(clip)

        # Kivy's way: the Fbo is in the canvas, so it renders each frame.
        with root.canvas:
            fbo = Fbo(size=(32, 32))
            Color(1, 1, 1, 1)
            Rectangle(texture=fbo.texture, pos=(200, 100), size=(64, 64))
        with fbo:
            ClearColor(1, 0, 0, 1)
            ClearBuffers()
            Color(0, 0, 1, 1)
            Rectangle(pos=(0, 0), size=(32, 16))
        self.fbo = fbo
        return root

app = Clipped()
app.run()
tick(4)
data = frame()
save(data, 'nui_stencil_fbo')
assert pixel(data, 50, 50) == (0, 255, 0, 255), pixel(data, 50, 50)    # inside the stencil
assert pixel(data, 150, 50)[:3] == (0, 0, 0), pixel(data, 150, 50)     # clipped away
assert pixel(data, 230, 110) == (0, 0, 255, 255), pixel(data, 230, 110) # fbo bottom half
assert pixel(data, 230, 150) == (255, 0, 0, 255), pixel(data, 230, 150) # fbo top half
print('OK')
'''


SHOWCASE_TEST = r'''
import time
sys.path.insert(0, os.path.join(ROOT, 'playground', 'src'))
from showcase.app import ShowcaseApp, SCREENS

def run_for(seconds):
    # Kivy's clock runs on real time, not on the dt the host passes.
    end = time.time() + seconds
    while time.time() < end:
        tick()
        time.sleep(1 / 60.)

app = ShowcaseApp()
app.run()
run_for(0.5)
for name in SCREENS:
    app.go(name)
    run_for(2.0)  # transition (shader ones included), then the screen's own clock
    assert app.manager.current == name, app.manager.current
    data = frame()
    save(data, 'nui_showcase_' + name)
    colors = {pixel(data, x, y) for x in range(0, WIDTH, 16) for y in range(0, HEIGHT, 16)}
    assert len(colors) > 3, (name, colors)

clock = app.manager.get_screen('clock')
assert clock.ticks > 5, clock.ticks
print('OK')
'''


def run(name, body):
    prelude = 'import ctypes, os, sys\n' + \
        'ROOT, KIVY, LIB, HEADLESS, SHOTS = {!r}, {!r}, {!r}, {!r}, {!r}\n'.format(
            ROOT, KIVY, LIB, HEADLESS, SHOTS) + \
        'WIDTH, HEIGHT = {}, {}\n'.format(WIDTH, HEIGHT)
    source = prelude + HOST + body
    # A real file, not `-c`: App.run() looks up the App class's source file
    # for its .kv.
    with tempfile.TemporaryDirectory() as tmp:
        script = os.path.join(tmp, 'nui_child.py')
        with open(script, 'w') as f:
            f.write(source)
        result = subprocess.run([sys.executable, script],
                                capture_output=True, text=True, timeout=180)
    ok = result.returncode == 0 and result.stdout.strip().endswith('OK')
    print('{} {}'.format('PASS' if ok else 'FAIL', name))
    if not ok:
        print(result.stdout[-4000:])
        print(result.stderr[-4000:])
    return ok


if __name__ == '__main__':
    results = [
        run('canvas: rectangles, ellipse, line, triangle fan', CANVAS_TEST),
        run('widgets: label and button text', WIDGETS_TEST),
        run('stencil view and fbo', STENCIL_FBO_TEST),
        run('showcase: every screen, shader transitions, clock', SHOWCASE_TEST),
    ]
    sys.exit(0 if all(results) else 1)
