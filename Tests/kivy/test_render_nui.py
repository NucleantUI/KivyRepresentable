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


TRANSFORM_STATE_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import (
    ApplyContextMatrix, Callback, ChangeState, Color, LoadIdentity,
    MatrixInstruction, PopMatrix, PopState, PushMatrix, PushState, Rectangle,
    Scale, Translate,
)
from kivy.graphics.context_instructions import Transform
from kivy.graphics.opengl import glDisable, GL_BLEND
from kivy.graphics.transformation import Matrix

calls = []

class Transforms(App):
    def build(self):
        root = Widget()
        with root.canvas:
            # Scale from the origin: (10, 10) 20x20 -> (20, 20) 40x40.
            PushMatrix()
            Scale(2, 2, 1, origin=(0, 0))
            Color(1, 0, 0, 1)
            Rectangle(pos=(10, 10), size=(20, 20))
            PopMatrix()

            # A matrix of its own: moved right by 100.
            PushMatrix()
            MatrixInstruction().matrix = Matrix().translate(100, 0, 0)
            Color(0, 1, 0, 1)
            Rectangle(pos=(0, 0), size=(20, 20))
            PopMatrix()

            # Transform: built, reset, built again.
            PushMatrix()
            t = Transform()
            t.translate(500, 0, 0)
            t.identity()
            t.translate(140, 0, 0)
            Color(0, 0, 1, 1)
            Rectangle(pos=(0, 0), size=(20, 20))
            PopMatrix()

            # LoadIdentity drops the Translate before it.
            PushMatrix()
            Translate(1000, 0)
            LoadIdentity()
            Color(1, 1, 1, 1)
            Rectangle(pos=(170, 0), size=(20, 20))
            PopMatrix()

            # ApplyContextMatrix: the modelview times itself, (110, 60) twice.
            PushMatrix()
            Translate(110, 60)
            ApplyContextMatrix(target_stack='modelview_mat', source_stack='modelview_mat')
            Color(1, 1, 0, 1)
            Rectangle(pos=(0, 0), size=(20, 20))
            PopMatrix()

            # State stack: color changed, then restored.
            Color(1, 0, 1, 1)
            PushState('color')
            ChangeState(color=(0, 1, 1, 1))
            Rectangle(pos=(0, 200), size=(20, 20))
            PopState('color')
            Rectangle(pos=(30, 200), size=(20, 20))

            # Callbacks run in the draw; reset_context brings blending back.
            Callback(lambda instr: calls.append('plain'))
            Color(1, 0, 0, 1)
            Rectangle(pos=(260, 180), size=(40, 40))
            Callback(lambda instr: (calls.append('reset'), glDisable(GL_BLEND)), reset_context=True)
            Color(0, 0, 1, 0.5)
            Rectangle(pos=(260, 180), size=(40, 40))
        return root

Transforms().run()
tick(4)
data = frame()
save(data, 'nui_transform_state')
assert pixel(data, 50, 50) == (255, 0, 0, 255), pixel(data, 50, 50)     # scaled
assert pixel(data, 15, 15)[:3] == (0, 0, 0), pixel(data, 15, 15)
assert pixel(data, 110, 10) == (0, 255, 0, 255), pixel(data, 110, 10)   # matrix
assert pixel(data, 150, 10) == (0, 0, 255, 255), pixel(data, 150, 10)   # transform
assert pixel(data, 180, 10) == (255, 255, 255, 255), pixel(data, 180, 10) # identity
assert pixel(data, 230, 130) == (255, 255, 0, 255), pixel(data, 230, 130) # applied twice
assert pixel(data, 120, 70)[:3] == (0, 0, 0), pixel(data, 120, 70)
assert pixel(data, 10, 210) == (0, 255, 255, 255), pixel(data, 10, 210)  # changed
assert pixel(data, 40, 210) == (255, 0, 255, 255), pixel(data, 40, 210)  # popped
assert near(pixel(data, 280, 200), (128, 0, 127, 255), 2), pixel(data, 280, 200)  # blended
assert 'plain' in calls and 'reset' in calls, calls
print('OK')
'''


VERTEX_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Mesh, Point, Quad, Triangle

def mesh(points, mode, indices=None):
    vertices = []
    for x, y in zip(points[::2], points[1::2]):
        vertices += [x, y, 0, 0]
    count = len(points) // 2
    Mesh(vertices=vertices, indices=indices or list(range(count)), mode=mode)

class Vertices(App):
    def build(self):
        root = Widget()
        with root.canvas:
            Color(1, 0, 0, 1)
            Triangle(points=[10, 180, 50, 180, 10, 220])
            Color(0, 1, 0, 1)
            Quad(points=[60, 180, 100, 180, 100, 220, 60, 220])
            Color(1, 1, 0, 1)
            Point(points=[120, 200, 140, 200], pointsize=3)
            Color(1, 1, 1, 1)
            mesh([160.5, 200.5, 170.5, 200.5], 'points')
            Color(0, 1, 1, 1)
            mesh([10.5, 110.5, 50.5, 110.5, 50.5, 150.5], 'line_strip')
            mesh([70.5, 110.5, 110.5, 110.5, 110.5, 150.5, 70.5, 150.5], 'line_loop')
            mesh([130.5, 110.5, 170.5, 110.5, 130.5, 150.5, 170.5, 150.5], 'lines')
            Color(1, 0, 1, 1)
            mesh([10, 10, 50, 10, 50, 50, 10, 50], 'triangles', [0, 1, 2, 0, 2, 3])
            mesh([70, 10, 110, 10, 70, 50, 110, 50], 'triangle_strip')
        return root

Vertices().run()
tick(4)
data = frame()
save(data, 'nui_vertices')

def around(x, y, color):
    return any(pixel(data, x + dx, y + dy)[:3] == color
               for dx in (-1, 0, 1) for dy in (-1, 0, 1))

assert pixel(data, 15, 185) == (255, 0, 0, 255), pixel(data, 15, 185)  # triangle
assert pixel(data, 45, 215)[:3] == (0, 0, 0), pixel(data, 45, 215)     # beyond its slant
assert pixel(data, 80, 200) == (0, 255, 0, 255), pixel(data, 80, 200)  # quad
assert pixel(data, 120, 200) == (255, 255, 0, 255)                      # points of Point
assert pixel(data, 140, 200) == (255, 255, 0, 255)
assert pixel(data, 130, 200)[:3] == (0, 0, 0)
assert around(160, 200, (255, 255, 255)) and around(170, 200, (255, 255, 255))  # GL points
assert pixel(data, 165, 200)[:3] == (0, 0, 0)
cyan = (0, 255, 255)
assert around(30, 110, cyan) and around(50, 130, cyan)        # line strip
assert not around(30, 130, cyan)                               # strips don't close
assert around(70, 130, cyan) and around(90, 150, cyan)         # loop closes
assert around(150, 110, cyan) and around(150, 150, cyan)       # two separate lines
assert not around(130, 130, cyan)
assert pixel(data, 30, 30) == (255, 0, 255, 255)               # triangles
assert pixel(data, 90, 30) == (255, 0, 255, 255)               # strip
print('OK')
'''


LINE_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, SmoothLine

class Lines(App):
    def build(self):
        root = Widget()
        with root.canvas:
            Color(1, 1, 1, 1)
            # Caps, width 5: none stops at the end point, square and round go past it.
            Line(points=[20, 225, 80, 225], width=5, cap='none')
            Line(points=[20, 205, 80, 205], width=5, cap='square')
            Line(points=[20, 185, 80, 185], width=5, cap='round')
            # Joints on a right angle: miter fills the outer corner, none doesn't.
            Line(points=[110, 225, 150, 225, 150, 185], width=5, joint='miter', cap='none')
            Line(points=[170, 225, 210, 225, 210, 185], width=5, joint='none', cap='none')
            Line(points=[230, 225, 270, 225, 270, 185], width=5, joint='bevel', cap='none')
            Line(points=[280, 225, 300, 225, 300, 185], width=5, joint='round', cap='none')
            # Dashed, width 1: a repeating texture along the line.
            Line(points=[20.5, 160.5, 300.5, 160.5], dash_length=10, dash_offset=10)
            Line(points=[20.5, 150.5, 300.5, 150.5], dashes=[5, 15])
            # Shapes.
            Line(circle=(50, 100, 30), width=2)
            Line(ellipse=(100, 70, 80, 50), width=2)
            Line(rectangle=(200, 70, 50, 50), width=2)
            Line(rounded_rectangle=(260, 70, 50, 50, 15), width=2)
            Line(bezier=[20, 20, 80, 60, 140, -20, 200, 20], width=2)
            Line(points=[210, 30, 300, 30], close=True, width=2)
            SmoothLine(points=[210, 10, 300, 50], width=2)
        return root

Lines().run()
tick(4)
data = frame()
save(data, 'nui_lines')

def lit(x, y):
    return pixel(data, x, y)[0] > 128

assert lit(50, 225)
assert not lit(84, 225), 'cap none ends at the point'
assert lit(83, 205), 'square cap'
assert lit(83, 185), 'round cap'
assert lit(154, 229), 'miter corner'
assert not lit(214, 229), 'no joint corner'
assert not lit(274, 229), 'bevel cuts the corner'
row = [lit(x, 160) for x in range(20, 300)]
assert any(row) and not all(row), 'dash_length / dash_offset'
row = [lit(x, 150) for x in range(20, 300)]
assert row.count(True) < row.count(False) and any(row), 'dashes'
assert lit(50, 70) or lit(50, 71) or lit(50, 69), 'circle bottom'
assert not lit(50, 100), 'circle inside'
assert any(lit(140, y) for y in range(68, 73)), 'ellipse bottom'
assert lit(200, 95), 'rectangle side'
assert not lit(225, 95), 'rectangle inside'
assert lit(285, 70) or lit(285, 71), 'rounded rectangle bottom'
assert not lit(261, 71), 'rounded corner'
assert any(lit(20, y) for y in range(18, 23)), 'bezier start'
assert any(lit(x, y) for x in range(250, 260) for y in range(25, 35)), 'smooth line'
print('OK')
'''


SMOOTH_EFFECTS_TEST = r'''
import tempfile
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import (
    BoxShadow, Color, Mesh, SmoothEllipse, SmoothQuad, SmoothRectangle,
    SmoothRoundedRectangle, SmoothTriangle,
)
from kivy.graphics.svg import Svg
from kivy.graphics.tesselator import Tesselator, WINDING_ODD, TYPE_POLYGONS

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80">
  <defs>
    <!-- Kivy's Svg reads gradients in user space only, and skips a
         coordinate of 0. -->
    <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="1" y1="1" x2="79" y2="1">
      <stop offset="0" stop-color="#ff0000"/>
      <stop offset="1" stop-color="#0000ff"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="80" height="40" fill="url(#g)"/>
  <rect x="0" y="40" width="80" height="40" fill="#00ff00"/>
</svg>"""

class Effects(App):
    def build(self):
        root = Widget()
        svg_path = os.path.join(tempfile.mkdtemp(), 'effects.svg')
        with open(svg_path, 'w') as f:
            f.write(SVG)
        with root.canvas:
            Color(1, 1, 1, 1)
            SmoothRectangle(pos=(10.3, 170.3), size=(50, 50))
            SmoothRoundedRectangle(pos=(70, 170), size=(50, 50), radius=[15])
            SmoothEllipse(pos=(130, 170), size=(50, 50))
            SmoothTriangle(points=[190, 170, 240, 170, 190, 220])
            SmoothQuad(points=[250, 170, 300, 175, 295, 220, 255, 215])

            # Concave L, filled by the tesselator.
            tess = Tesselator()
            tess.add_contour([10, 10, 90, 10, 90, 40, 40, 40, 40, 100, 10, 100])
            assert tess.tesselate(WINDING_ODD, TYPE_POLYGONS)
            Color(1, 0.5, 0, 1)
            for vertices, indices in tess.meshes:
                Mesh(vertices=vertices, indices=indices, mode='triangle_fan')

            Color(0, 0, 0, 1)
            BoxShadow(pos=(230, 40), size=(60, 60), blur_radius=20)
        svg = Svg(svg_path)
        from kivy.graphics import PushMatrix, PopMatrix, Translate
        root.canvas.add(PushMatrix())
        root.canvas.add(Translate(120, 40))
        root.canvas.add(svg)
        root.canvas.add(PopMatrix())
        return root

from kivy.core.window import Window
Window.clearcolor = (0.5, 0.5, 0.5, 1)
Effects().run()
tick(4)
data = frame()
save(data, 'nui_smooth_effects')

def edge(points):
    """Some pixel along these is between the shape and the background."""
    return any(140 < pixel(data, x, y)[0] < 250 for x, y in points)

assert pixel(data, 35, 195) == (255, 255, 255, 255)
# On the diagonal, where the edge cuts pixels part way.
assert edge([(136 + i, 211 + j) for i in range(4) for j in range(4)]), 'smooth ellipse edge'
assert edge([(215 + k, 195 - k) for k in range(-3, 4)]) or edge([(214, y) for y in range(190, 200)]), 'smooth triangle edge'
assert pixel(data, 95, 195) == (255, 255, 255, 255)
assert pixel(data, 155, 195) == (255, 255, 255, 255)
assert pixel(data, 205, 180) == (255, 255, 255, 255)
assert pixel(data, 275, 195) == (255, 255, 255, 255)
assert pixel(data, 20, 70) == (255, 128, 0, 255), pixel(data, 20, 70)    # L, upright
assert pixel(data, 80, 20) == (255, 128, 0, 255), pixel(data, 80, 20)    # L, foot
assert pixel(data, 70, 70)[:3] == (128, 128, 128), pixel(data, 70, 70)  # notch
assert pixel(data, 260, 70)[0] < 60, pixel(data, 260, 70)                # shadow core
assert 60 < pixel(data, 225, 70)[0] < 128, pixel(data, 225, 70)          # blurred
# The svg: y down in the file, so its first rect lands on top.
left, right = pixel(data, 124, 100), pixel(data, 196, 100)
assert left[0] > 200 and left[2] < 60, left      # gradient, red end
assert right[2] > 200 and right[0] < 60, right   # blue end
assert pixel(data, 160, 60)[:3] == (0, 255, 0), pixel(data, 160, 60)
print('OK')
'''


SCISSOR_TEXTURE_TEST = r'''
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.core.image import ImageData
from kivy.graphics import Color, Rectangle, ScissorPop, ScissorPush
from kivy.graphics.texture import Texture

def quad_texture(filter):
    # 2x2: red, green / blue, white (bottom row first)
    tex = Texture.create(size=(2, 2), colorfmt='rgba')
    tex.blit_buffer(bytes([255, 0, 0, 255, 0, 255, 0, 255,
                           0, 0, 255, 255, 255, 255, 255, 255]), colorfmt='rgba', bufferfmt='ubyte')
    tex.mag_filter = filter
    tex.min_filter = filter
    return tex

class Textures(App):
    def build(self):
        root = Widget()
        with root.canvas:
            # Scissor, nested: only the overlap of both.
            ScissorPush(x=10, y=170, width=60, height=60)
            ScissorPush(x=40, y=150, width=60, height=60)
            Color(0, 1, 0, 1)
            Rectangle(pos=(0, 140), size=(120, 100))
            ScissorPop()
            ScissorPop()

            Color(1, 1, 1, 1)
            Rectangle(texture=quad_texture('nearest'), pos=(130, 170), size=(40, 40))
            Rectangle(texture=quad_texture('linear'), pos=(180, 170), size=(40, 40))

            # blit_data from an ImageData; rgb, so converted on upload.
            data = ImageData(2, 1, 'rgb', bytes([255, 255, 0, 0, 255, 255]))
            tex = Texture.create(size=(2, 1), colorfmt='rgb')
            tex.blit_data(data)
            tex.mag_filter = 'nearest'
            Rectangle(texture=tex, pos=(230, 170), size=(40, 40))

            # A sub-rectangle blit into a texture already filled.
            sub = quad_texture('nearest')
            sub.blit_buffer(bytes([255, 0, 255, 255]), pos=(1, 1), size=(1, 1), colorfmt='rgba')
            Rectangle(texture=sub, pos=(275, 170), size=(40, 40))

            # Wrap: texture coordinates 0..2 draw it twice each way.
            for i, wrap in enumerate(('repeat', 'mirrored_repeat', 'clamp_to_edge')):
                tex = quad_texture('nearest')
                tex.wrap = wrap
                Rectangle(texture=tex, pos=(10 + i * 70, 80), size=(60, 60),
                          tex_coords=(0, 0, 2, 0, 2, 2, 0, 2))

            # Mipmaps: a 1px checker shrunk 8x averages out grey.
            checker = bytes(v for y in range(64) for x in range(64)
                            for v in ([255] * 3 if (x + y) % 2 else [0] * 3) + [255])
            for i, mipmap in enumerate((True, False)):
                tex = Texture.create(size=(64, 64), colorfmt='rgba', mipmap=mipmap)
                tex.blit_buffer(checker, colorfmt='rgba', bufferfmt='ubyte')
                if mipmap:
                    tex.min_filter = 'linear_mipmap_linear'
                else:
                    tex.min_filter = 'nearest'
                Rectangle(texture=tex, pos=(230 + i * 40, 90), size=(8, 8))
        return root

Textures().run()
tick(4)
data = frame()
save(data, 'nui_scissor_texture')
assert pixel(data, 55, 190) == (0, 255, 0, 255)       # inside both
assert pixel(data, 20, 190)[:3] == (0, 0, 0)          # first only
assert pixel(data, 90, 160)[:3] == (0, 0, 0)          # second only
assert pixel(data, 140, 180) == (255, 0, 0, 255), pixel(data, 140, 180)    # nearest
assert pixel(data, 160, 180) == (0, 255, 0, 255), pixel(data, 160, 180)
assert pixel(data, 140, 200) == (0, 0, 255, 255), pixel(data, 140, 200)
assert pixel(data, 160, 200) == (255, 255, 255, 255), pixel(data, 160, 200)
mid = pixel(data, 200, 190)                            # linear: all four mixed
assert all(40 < c < 220 for c in mid[:3]), mid
assert pixel(data, 240, 190) == (255, 255, 0, 255), pixel(data, 240, 190)  # blit_data
assert pixel(data, 260, 190) == (0, 255, 255, 255), pixel(data, 260, 190)
assert pixel(data, 305, 200) == (255, 0, 255, 255), pixel(data, 305, 200)  # sub blit
assert pixel(data, 285, 180) == (255, 0, 0, 255), pixel(data, 285, 180)
# repeat: red, green, red, green along the bottom row of tiles
assert [pixel(data, 10 + 15 * k + 7, 87)[:3] for k in range(4)] == \
    [(255, 0, 0), (0, 255, 0), (255, 0, 0), (0, 255, 0)], [pixel(data, 10 + 15 * k + 7, 87) for k in range(4)]
# mirrored: red, green, green, red
assert [pixel(data, 80 + 15 * k + 7, 87)[:3] for k in range(4)] == \
    [(255, 0, 0), (0, 255, 0), (0, 255, 0), (255, 0, 0)], [pixel(data, 80 + 15 * k + 7, 87) for k in range(4)]
# clamp: red, green, then green stretched
assert [pixel(data, 150 + 15 * k + 7, 87)[:3] for k in range(4)] == \
    [(255, 0, 0), (0, 255, 0), (0, 255, 0), (0, 255, 0)], [pixel(data, 150 + 15 * k + 7, 87) for k in range(4)]
grey = pixel(data, 234, 94)
assert 100 < grey[0] < 155, grey                       # mipmapped: averaged
sharp = {pixel(data, 270 + x, 90 + y)[:3] for x in range(8) for y in range(8)}
assert sharp <= {(0, 0, 0), (255, 255, 255)}, sharp     # no mipmaps, nearest: texels
print('OK')
'''


DEPTH_3D_TEST = r'''
from kivy.app import App
# As Kivy's 3D example: the window (and its GL) exists from here on, before
# any widget; the RenderContexts below make their shaders before
# Widget.__init__ would have made it.
from kivy.core.window import Window
from kivy.uix.widget import Widget
from kivy.graphics import (
    Callback, Color, Mesh, PopMatrix, PushMatrix, RenderContext, Rotate,
    Translate, UpdateNormalMatrix,
)
from kivy.graphics.opengl import glDisable, glEnable, GL_DEPTH_TEST
from kivy.graphics.transformation import Matrix

sys.path.insert(0, os.path.join(KIVY or os.path.join(ROOT, 'kivy2x'), 'examples', '3Drendering'))
from objloader import ObjFile
EXAMPLE = os.path.dirname(sys.modules['objloader'].__file__)

FLAT_VS = """
#ifdef GL_ES
    precision highp float;
#endif
attribute vec3 v_pos;
attribute vec4 v_color;
uniform mat4 modelview_mat;
uniform mat4 projection_mat;
varying vec4 color_out;
void main (void) {
    color_out = v_color;
    gl_Position = projection_mat * modelview_mat * vec4(v_pos, 1.0);
}
"""

FLAT_FS = """
#ifdef GL_ES
    precision highp float;
#endif
varying vec4 color_out;
void main (void) {
    gl_FragColor = color_out;
}
"""

def quad(z, rgba, half):
    vertices = []
    for x, y in ((-half, -half), (half, -half), (half, half), (-half, half)):
        vertices += [x, y, z] + list(rgba)
    return Mesh(vertices=vertices, indices=[0, 1, 2, 2, 3, 0], mode='triangles',
                fmt=[(b'v_pos', 3, 'float'), (b'v_color', 4, 'float')])

class Scene(Widget):
    """Two quads on the left half: the near one (red) drawn first, the far
    one (blue, bigger) after. Depth test keeps red in front."""
    def __init__(self, depth, **kwargs):
        self.canvas = RenderContext(vs=FLAT_VS, fs=FLAT_FS)
        super().__init__(**kwargs)
        self.canvas['projection_mat'] = Matrix().view_clip(-1, 1, -1, 1, 1, 100, 1)
        with self.canvas:
            if depth:
                Callback(lambda *_: glEnable(GL_DEPTH_TEST))
            PushMatrix()
            Translate(-1 if depth else 1, 0, 0)
            quad(-2, (1, 0, 0, 1), 0.3)
            quad(-4, (0, 0, 1, 1), 1.2)
            PopMatrix()
            if depth:
                Callback(lambda *_: glDisable(GL_DEPTH_TEST))

class Monkey(Widget):
    """Kivy's 3D example: its shader, its obj file, normals from
    UpdateNormalMatrix; the mesh's vertex format is v_pos/v_normal/v_tc0."""
    def __init__(self, **kwargs):
        self.canvas = RenderContext(compute_normal_mat=True)
        self.canvas.shader.source = os.path.join(EXAMPLE, 'simple.glsl')
        scene = ObjFile(os.path.join(EXAMPLE, 'monkey.obj'))
        super().__init__(**kwargs)
        self.canvas['projection_mat'] = Matrix().view_clip(-1.33, 1.33, -1, 1, 1, 100, 1)
        with self.canvas:
            Callback(lambda *_: glEnable(GL_DEPTH_TEST))
            PushMatrix()
            Translate(0, 0, -3)
            Rotate(20, 0, 1, 0)
            m = list(scene.objects.values())[0]
            UpdateNormalMatrix()
            Mesh(vertices=m.vertices, indices=m.indices, fmt=m.vertex_format, mode='triangles')
            PopMatrix()
            Callback(lambda *_: glDisable(GL_DEPTH_TEST))

class Depth(App):
    def build(self):
        mode = os.environ['DEPTH_MODE']
        if mode == 'monkey':
            return Monkey()
        root = Widget()
        root.add_widget(Scene(True, size=(WIDTH, HEIGHT)))
        root.add_widget(Scene(False, size=(WIDTH, HEIGHT)))
        return root

Depth().run()
tick(4)
data = frame()
save(data, 'nui_3d_' + os.environ['DEPTH_MODE'])
if os.environ['DEPTH_MODE'] == 'monkey':
    lit = [pixel(data, x, y)[0] for x in range(0, WIDTH, 4) for y in range(0, HEIGHT, 4)]
    assert sum(1 for v in lit if v > 30) > 200, 'monkey not drawn'
    assert pixel(data, 2, 2)[:3] == (0, 0, 0)
    shades = {v // 32 for v in lit if v > 0}
    assert len(shades) >= 4, shades      # lit by its normals, not flat
else:
    # Left: depth tested, the near red quad wins. Right: drawn in order, blue covers it.
    assert pixel(data, 80, 120) == (255, 0, 0, 255), pixel(data, 80, 120)
    assert pixel(data, 240, 120) == (0, 0, 255, 255), pixel(data, 240, 120)
    assert pixel(data, 100, 90) == (0, 0, 255, 255), pixel(data, 100, 90)
print('OK')
'''


CIRCLE_TEST = r"""
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import (
    Color, Ellipse, Rectangle, RenderContext, StencilPop, StencilPush,
    StencilUnUse, StencilUse,
)
from kivy.graphics.texture import Texture

SOLID = '''
$HEADER$
void main (void) {
    gl_FragColor = vec4(0.0, 1.0, 1.0, 1.0);
}
'''

class Circles(App):
    def build(self):
        root = Widget()
        with root.canvas:
            Color(1, 0, 0, 1)
            Ellipse(pos=(5, 140), size=(90, 90))
            Color(0, 1, 0, 1)
            Ellipse(pos=(100, 140), size=(90, 90), angle_start=0, angle_end=90)
            Color(0, 0, 1, 1)
            Ellipse(pos=(195, 140), size=(90, 90), angle_start=0, angle_end=270)
            Color(1, 1, 0, 1)
            Ellipse(pos=(290, 140), size=(25, 90))

            # Textured: the texture's four texels in its four quarters.
            tex = Texture.create(size=(2, 2), colorfmt='rgba')
            tex.blit_buffer(bytes([255, 0, 0, 255, 0, 255, 0, 255,
                                   0, 0, 255, 255, 255, 255, 255, 255]),
                            colorfmt='rgba', bufferfmt='ubyte')
            tex.mag_filter = 'nearest'
            Color(1, 1, 1, 1)
            Ellipse(pos=(5, 10), size=(60, 60), texture=tex)

            # As a stencil mask: the rectangle shows through the circle only.
            StencilPush()
            Ellipse(pos=(80, 10), size=(60, 60))
            StencilUse()
            Color(1, 0, 1, 1)
            Rectangle(pos=(80, 10), size=(60, 60))
            StencilUnUse()
            Ellipse(pos=(80, 10), size=(60, 60))
            StencilPop()

            # Explicit segments: Kivy's polygon, a diamond.
            Color(1, 0.5, 0, 1)
            Ellipse(pos=(230, 10), size=(60, 60), segments=4)

        # In a context with its own shader, that shader fills the ellipse.
        context = RenderContext(use_parent_projection=True, use_parent_modelview=True)
        context.shader.fs = SOLID
        with context:
            Ellipse(pos=(155, 10), size=(60, 60))
        root.canvas.add(context)
        return root

Circles().run()
tick(4)
data = frame()
save(data, 'nui_circles')

def rgb(x, y):
    return pixel(data, x, y)[:3]

# Full circle: center filled, box corner empty, the diagonal edge antialiased.
assert rgb(50, 185) == (255, 0, 0)
assert rgb(7, 142) == (0, 0, 0)
edge = [pixel(data, 15 + i, 213 + j)[0] for i in range(6) for j in range(6)]
assert any(0 < v < 255 for v in edge), edge
# Quarter, 0..90: the top right only (Kivy's angles: clockwise from the top).
assert rgb(160, 200) == (0, 255, 0)
assert rgb(130, 200) == (0, 0, 0)
assert rgb(160, 165) == (0, 0, 0)
# 0..270, past half way: all but the top left quarter.
assert rgb(220, 200) == (0, 0, 0), rgb(220, 200)
assert rgb(260, 200) == (0, 0, 255) and rgb(260, 165) == (0, 0, 255) and rgb(220, 165) == (0, 0, 255)
# Stretched: tall and narrow.
assert rgb(302, 185) == (255, 255, 0)
assert rgb(301, 225) == (255, 255, 0)
assert rgb(292, 143) == (0, 0, 0)
# Textured.
assert rgb(25, 30) == (255, 0, 0) and rgb(45, 30) == (0, 255, 0)
assert rgb(25, 50) == (0, 0, 255) and rgb(45, 50) == (255, 255, 255)
assert rgb(7, 12) == (0, 0, 0)
# Stencil: through the circle, not its box's corner.
assert rgb(110, 40) == (255, 0, 255)
assert rgb(83, 13) == (0, 0, 0)
# Own shader: its color, still round.
assert rgb(185, 40) == (0, 255, 255)
assert rgb(158, 13) == (0, 0, 0)
# Diamond: the box's corner region is out, though a circle would cover it.
assert rgb(260, 40) == (255, 128, 0)
assert rgb(241, 21) == (0, 0, 0), rgb(241, 21)
print('OK')
"""


RING_TEST = r"""
from math import cos, radians, sin
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, RenderContext, SmoothLine

SOLID = '''
$HEADER$
void main (void) {
    gl_FragColor = vec4(0.0, 1.0, 1.0, 1.0);
}
'''

lines = {}

class Rings(App):
    def build(self):
        root = Widget()
        with root.canvas:
            # Full ring, width 4: the stroke is 4 each side of the circle.
            Color(1, 0, 0, 1)
            lines['full'] = Line(circle=(45, 190, 35), width=4)
            # Quarter arcs from the top, clockwise: the caps at the top end.
            Color(0, 1, 0, 1)
            Line(circle=(130, 190, 35, 0, 90), width=4, cap='none')
            Color(0, 0, 1, 1)
            Line(circle=(215, 190, 35, 0, 90), width=4, cap='square')
            Color(1, 1, 0, 1)
            Line(circle=(290, 190, 25, 0, 90), width=4, cap='round')

            # Width 1: a one pixel line; and dashed, along the circle.
            Color(1, 1, 1, 1)
            Line(circle=(40.5, 110.5, 30))
            lines['dashed'] = Line(circle=(110.5, 110.5, 30), dash_length=8, dash_offset=8)
            # An ellipse, and an ellipse's arc closed through the center.
            Color(1, 0, 1, 1)
            Line(ellipse=(150, 80, 80, 50), width=3)
            Color(0, 1, 0, 1)
            Line(ellipse=(245, 80, 70, 60, 0, 90), width=2, close=True,
                 close_mode='center-connected')

            # Half a circle closed by its chord.
            Color(1, 1, 1, 1)
            Line(circle=(40, 40, 30, 0, 180), width=2, close=True)
            # Half transparent: one layer everywhere, no overlaps.
            Color(1, 1, 1, 0.5)
            Line(circle=(110, 40, 25), width=6)
            Color(1, 1, 1, 1)
            SmoothLine(circle=(170, 40, 25), width=2)
            # Explicit segments: Kivy's polygon, a diamond.
            Color(1, 0.5, 0, 1)
            Line(circle=(230, 40, 25, 0, 360, 4), width=2)

        # In a context with its own shader, that shader draws the polyline.
        context = RenderContext(use_parent_projection=True, use_parent_modelview=True)
        context.shader.fs = SOLID
        with context:
            Line(circle=(290, 40, 22), width=2)
        root.canvas.add(context)
        return root

Rings().run()
tick(4)
data = frame()
save(data, 'nui_rings')

def rgb(x, y):
    return pixel(data, x, y)[:3]

# Full ring: on it, inside and outside it, and the edge antialiased.
assert rgb(45, 225) == (255, 0, 0), rgb(45, 225)
assert rgb(45, 190) == (0, 0, 0) and rgb(45, 218) == (0, 0, 0) and rgb(45, 231) == (0, 0, 0)
edge = [pixel(data, 68 + i, 213 + j)[0] for i in range(6) for j in range(6)]
assert any(0 < v < 255 for v in edge), edge
# Caps at the arc's start, the top: none stops there, square goes on 4 past it
# with corners, round 4 past it, round.
assert rgb(154, 214) == (0, 255, 0)
assert rgb(133, 225) == (0, 255, 0) and rgb(126, 225) == (0, 0, 0)
assert rgb(212, 225) == (0, 0, 255) and rgb(212, 228) == (0, 0, 255) and rgb(209, 225) == (0, 0, 0)
assert rgb(287, 215) == (255, 255, 0) and rgb(286, 218) == (0, 0, 0), rgb(286, 218)
# The arcs' other ends, the right: past them, nothing.
assert rgb(165, 191) == (0, 255, 0) and rgb(165, 187) == (0, 0, 0)
# Width 1: one pixel, solid where it is on the pixel's center.
assert rgb(70, 110) == (255, 255, 255) and rgb(72, 110) == (0, 0, 0) and rgb(40, 110) == (0, 0, 0)
on = [pixel(data, int(110.5 + 30 * sin(radians(a))), int(110.5 + 30 * cos(radians(a))))[0] > 128
      for a in range(0, 360, 2)]
assert 0.3 < on.count(True) / len(on) < 0.7, on
# Dashes are runs, not noise.
assert sum(1 for i in range(len(on)) if on[i] != on[i - 1]) < 40, on
# Ellipse: top, right, at 45 degrees on it, not its center.
assert rgb(190, 129) == (255, 0, 255) and rgb(229, 105) == (255, 0, 255)
assert rgb(218, 122) == (255, 0, 255) and rgb(190, 105) == (0, 0, 0)
# The pie's outline: both radii and the arc; not inside, not the other side.
assert rgb(280, 125) == (0, 255, 0) and rgb(297, 110) == (0, 255, 0)
assert rgb(304, 131) == (0, 255, 0), rgb(304, 131)
assert rgb(290, 120) == (0, 0, 0) and rgb(270, 120) == (0, 0, 0)
# Chord: the half circle's straight side; inside it empty.
assert rgb(40, 40) == (255, 255, 255) and rgb(69, 40) == (255, 255, 255)
assert rgb(55, 40) == (0, 0, 0) and rgb(25, 40) == (0, 0, 0)
# Half transparent: the same everywhere around it.
values = [pixel(data, int(110 + 25 * sin(radians(a))), int(40 + 25 * cos(radians(a))))[0]
          for a in range(0, 360, 15)]
assert all(120 <= v <= 136 for v in values), values
# SmoothLine.
assert pixel(data, 170, 65)[0] > 200 and rgb(170, 40) == (0, 0, 0)
# Diamond: the circle at 45 degrees is outside it; its edge is lit.
assert rgb(247, 57) == (0, 0, 0) and rgb(242, 52) == (255, 128, 0)
# Own shader: its color, as a polyline.
assert any(rgb(290, y) == (0, 255, 255) for y in range(60, 64))
# Points are still made, when asked for.
assert len(lines['full'].points) == 2 * 183, len(lines['full'].points)
assert lines['full'].circle == (45, 190, 35, 0, 360, 183), lines['full'].circle
print('OK')
"""


FLAT_RING_TEST = r"""
from math import cos, radians, sin
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Line, PopMatrix, PushMatrix, Scale

class Flat(App):
    def build(self):
        root = Widget()
        with root.canvas:
            Color(1, 1, 1, 1)
            # Flatter than the stroke is wide at the tips.
            Line(ellipse=(10, 200, 300, 20), width=3)
            # An arc on a flat ellipse: it comes back around behind its end.
            Line(ellipse=(10, 150, 300, 40, 30, 250), width=5, cap='round')
            Line(ellipse=(10, 100, 150, 40, 200, 340), width=6, cap='square')
            Line(ellipse=(170, 60, 20, 120), width=2)
            # Scaled 3 times: width 1 stays one pixel, width 2 grows to 12.
            PushMatrix()
            Scale(3, 3, 1)
            Line(circle=(20, 20, 12))
            Line(circle=(45, 20, 10), width=2)
            PopMatrix()
        return root

Flat().run()
tick(4)
data = frame()
save(data, 'nui_flat_rings')

def lit(x, y):
    return pixel(data, x, y)[0] > 128

def on(cx, cy, rx, ry, a):
    return int(cx + rx * sin(radians(a))), int(cy + ry * cos(radians(a)))

# The flat ring: its top, its tip, not its middle.
assert lit(160, 219) and lit(11, 210) and not lit(160, 210)
# The arc: on it, round past its end at 250 degrees, and nothing in its gap
# (from 250 round to 30), though that is behind the end's normal.
assert lit(*on(160, 170, 150, 20, 120)) and lit(*on(160, 170, 150, 20, 200))
assert lit(*on(160, 170, 150, 20, 252))
for a in (275, 290, 310, 330, 350, 10):
    assert not lit(*on(160, 170, 150, 20, a)), a
# Square caps at 200 and 340 degrees, nothing between them over the top.
assert lit(*on(85, 120, 75, 20, 270))
assert not lit(*on(85, 120, 75, 20, 0)) and not lit(*on(85, 120, 75, 20, 160))
# Tall and narrow.
assert lit(180, 179) and lit(170, 120) and not lit(180, 120)
# Scaled: a one pixel line, and a 12 pixel one.
# (it falls between two pixels: half each, one pixel's worth in all)
thin = [pixel(data, x, 60)[0] for x in range(88, 98)]
assert 200 <= sum(thin) <= 330 and sum(1 for v in thin if v) <= 3, thin
thick = [lit(x, 60) for x in range(97, 125)]
assert 11 <= thick.count(True) <= 13, thick
print('OK')
"""


SKIA_TEXTURE_TEST = r"""
from kivy.app import App
from kivy.uix.widget import Widget
from kivy.graphics import Color, Rectangle
from kivy.graphics.texture import Texture

headless.kivy_nui_headless_skia_pattern.argtypes = [ctypes.c_uint32, ctypes.c_int32, ctypes.c_int32]
headless.kivy_nui_headless_skia_pattern.restype = ctypes.c_bool

class SkiaTexture(App):
    def build(self):
        root = Widget()
        # A texture of Kivy's own, flipped as Kivy flips its images: Skia
        # draws its first row at the top, as image data comes.
        self.texture = Texture.create(size=(128, 96), colorfmt='rgba')
        self.texture.flip_vertical()
        with root.canvas:
            Color(1, 1, 1, 1)
            Rectangle(texture=self.texture, pos=(20, 20), size=(128, 96))
            # The same texture again, tinted and half the size: Kivy's
            # drawing of it doesn't change.
            Color(0, 1, 0, 1)
            Rectangle(texture=self.texture, pos=(180, 40), size=(64, 48))
        return root

app = SkiaTexture()
app.run()
tick(2)
assert headless.kivy_nui_headless_skia_pattern(app.texture.id, 128, 96)
# The texture's pixels changed under Kivy: its canvas redraws when asked.
app.root.canvas.ask_update()
tick(2)
data = frame()
save(data, 'nui_skia_texture')

def near_color(x, y, color):
    return near(pixel(data, x, y), color, 8)

# Red band over the top quarter, blue circle at the texture's (64, 60) from
# the top, white elsewhere; the text is dark somewhere in its corner.
assert near_color(84, 110, (255, 0, 0, 255)), pixel(data, 84, 110)
assert near_color(84, 56, (0, 0, 255, 255)), pixel(data, 84, 56)
assert near_color(140, 46, (255, 255, 255, 255)), pixel(data, 140, 46)
assert near_color(30, 80, (255, 255, 255, 255)), pixel(data, 30, 80)
text = [pixel(data, x, y)[0] for x in range(22, 60) for y in range(22, 38)]
assert min(text) < 100 and max(text) > 200, (min(text), max(text))
# The tinted copy: red band green-tinted is black, white is green.
assert near_color(212, 84, (0, 0, 0, 255)), pixel(data, 212, 84)
assert near_color(236, 50, (0, 255, 0, 255)), pixel(data, 236, 50)

# Drawn again: Skia draws over the same texture, Kivy shows the new pixels.
assert headless.kivy_nui_headless_skia_pattern(app.texture.id, 128, 96)
app.root.canvas.ask_update()
tick(1)
data = frame()
assert near_color(84, 110, (255, 0, 0, 255))
print('OK')
"""


PROVIDERS_TEST = r"""
import io
from PIL import Image as PILImage
from kivy.app import App
from kivy.core.image import Image as CoreImage, ImageLoader
from kivy.core.text import Label as CoreLabel
from kivy.graphics import Color, Rectangle
from kivy.uix.button import Button
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.image import Image
from kivy.uix.label import Label

# Kivy picked the host's providers.
assert CoreLabel.__name__ == 'LabelNUI', CoreLabel
assert ImageLoader.loaders[0].__name__ == 'ImageLoaderNUI', ImageLoader.loaders

# A 40x40 PNG: red over green, as an image file's rows go (first at the top).
picture = PILImage.new('RGBA', (40, 40), (0, 255, 0, 255))
picture.paste((255, 0, 0, 255), (0, 0, 40, 20))
png_path = os.path.join(SHOTS, 'nui_providers_source.png')
picture.save(png_path)
png_bytes = io.BytesIO()
picture.save(png_bytes, 'png')
# An SVG sized by its viewBox: red over blue.
svg_path = os.path.join(SHOTS, 'nui_providers_source.svg')
with open(svg_path, 'w') as f:
    f.write("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'>"
            "<rect width='20' height='10' fill='#ff0000'/>"
            "<rect y='10' width='20' height='10' fill='#0000ff'/>"
            "<circle cx='10' cy='10' r='3' fill='#ffffff'/></svg>")

class Providers(App):
    def build(self):
        root = FloatLayout()
        def add(widget, pos, size):
            widget.size_hint = (None, None)
            widget.pos, widget.size = pos, size
            root.add_widget(widget)
            return widget
        self.plain = add(Label(text='Skia text', font_size=40), (10, 180), (300, 56))
        add(Label(text='[b]Bold[/b] [color=ff0000]red[/color] [u]under[/u]',
                  markup=True, font_size=24), (10, 130), (300, 40))
        add(Label(text='Out', font_size=30, color=(1, 1, 0, 1),
                  outline_width=3, outline_color=(0, 0, 1, 1)), (220, 10), (100, 60))
        add(Image(source=png_path, fit_mode='fill'), (10, 10), (40, 40))
        add(Image(source=svg_path, fit_mode='fill'), (10, 70), (40, 40))
        add(Button(text='Atlas'), (120, 10), (90, 50))
        memory = CoreImage(io.BytesIO(png_bytes.getvalue()), ext='png')
        with root.canvas:
            Color(1, 1, 1, 1)
            Rectangle(texture=memory.texture, pos=(60, 10), size=(40, 40))
            # No texture: Kivy's default one, its default.png through the
            # same loader.
            Color(0, 0, 1, 1)
            Rectangle(pos=(150, 80), size=(30, 30))
        return root

app = Providers()
app.run()
tick(6)
data = frame()
save(data, 'nui_providers')

def region(x0, x1, y0, y1, step=1):
    return [pixel(data, x, y) for x in range(x0, x1, step) for y in range(y0, y1, step)]

# Plain text: measured to a sensible size, drawn white where the label is.
w, h = app.plain.texture_size
assert 120 <= w <= 230 and 40 <= h <= 64, (w, h)
assert any(p[0] > 220 and p[1] > 220 and p[2] > 220 for p in region(10, 310, 180, 236, 2))
# Markup: the red word in red.
assert any(p[0] > 200 and p[1] < 60 and p[2] < 60 for p in region(10, 310, 130, 170)), 'no red word'
# Outline: blue around yellow.
out = region(220, 320, 10, 70)
assert any(p[2] > 200 and p[0] < 60 for p in out), 'no blue outline'
assert any(p[0] > 200 and p[1] > 200 and p[2] < 60 for p in out), 'no yellow text'
# Images, from a file and from memory: upright, red over green.
for x in (30, 80):
    assert near(pixel(data, x, 42), (255, 0, 0, 255), 8), (x, pixel(data, x, 42))
    assert near(pixel(data, x, 18), (0, 255, 0, 255), 8), (x, pixel(data, x, 18))
# The SVG: upright, red over blue, a white dot in the middle.
assert near(pixel(data, 20, 104), (255, 0, 0, 255), 8), pixel(data, 20, 104)
assert near(pixel(data, 20, 76), (0, 0, 255, 255), 8), pixel(data, 20, 76)
assert near(pixel(data, 30, 90), (255, 255, 255, 255), 8), pixel(data, 30, 90)
# The Button's background is Kivy's theme atlas, a PNG through the same loader.
assert any(near(p, (88, 88, 88, 255), 40) for p in region(122, 208, 12, 58, 3)), 'no button background'
# keep_data: the host decodes into bytes Kivy keeps and reads back.
kept = CoreImage(png_path, keep_data=True)
assert kept.size == (40, 40)
colors = {tuple(round(c) for c in kept.read_pixel(5, y)) for y in (5, 35)}
assert colors == {(1, 0, 0, 1), (0, 1, 0, 1)}, colors
kept = CoreImage(svg_path, keep_data=True)
assert kept.size == (20, 20)
colors = {tuple(round(c) for c in kept.read_pixel(1, y)) for y in (1, 18)}
assert colors == {(1, 0, 0, 1), (0, 0, 1, 1)}, colors
assert near(pixel(data, 165, 95), (0, 0, 255, 255), 8), pixel(data, 165, 95)
# A graphics context reload recreates every texture empty; the host's
# images are drawn into them again.
from kivy.graphics.context import get_context
get_context().reload()
app.root.canvas.ask_update()   # a frame drawn after it
tick(6)
data = frame()
save(data, 'nui_providers_reloaded')
for x in (30, 80):
    assert near(pixel(data, x, 42), (255, 0, 0, 255), 8), ('reloaded', x, pixel(data, x, 42))
    assert near(pixel(data, x, 18), (0, 255, 0, 255), 8), ('reloaded', x, pixel(data, x, 18))
assert near(pixel(data, 20, 104), (255, 0, 0, 255), 8), ('reloaded', pixel(data, 20, 104))
assert near(pixel(data, 165, 95), (0, 0, 255, 255), 8), ('reloaded', pixel(data, 165, 95))
print('OK')
"""


def run(name, body, env=None):
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
                                capture_output=True, text=True, timeout=180,
                                env=dict(os.environ, **(env or {})))
    ok = result.returncode == 0 and result.stdout.strip().endswith('OK')
    print('{} {}'.format('PASS' if ok else 'FAIL', name))
    if not ok:
        # Kivy's and MoltenVK's logs left out: what failed is in the rest.
        def plain(text):
            return '\n'.join(line for line in text.splitlines()
                             if not line.startswith(('\t', '[INFO', '[DEBUG', '[mvk-')))
        print('exit code', result.returncode)
        print(plain(result.stdout)[-4000:])
        print(plain(result.stderr)[-4000:])
    return ok


if __name__ == '__main__':
    tests = [
        ('canvas: rectangles, ellipse, line, triangle fan', CANVAS_TEST, None),
        ('circles: shader ellipse, arcs, texture, stencil, fallbacks', CIRCLE_TEST, None),
        ('rings: shader circle and ellipse lines, caps, dashes, closing', RING_TEST, None),
        ('rings: flat ellipses, scaled', FLAT_RING_TEST, None),
        ('skia: drawing into a kivy texture', SKIA_TEXTURE_TEST, None),
        ('providers: skia text, images and svg into kivy textures', PROVIDERS_TEST, None),
        ('widgets: label and button text', WIDGETS_TEST, None),
        ('stencil view and fbo', STENCIL_FBO_TEST, None),
        ('showcase: every screen, shader transitions, clock', SHOWCASE_TEST, None),
        ('transforms, state stack, callbacks', TRANSFORM_STATE_TEST, None),
        ('vertex instructions and mesh modes', VERTEX_TEST, None),
        ('line caps, joints, dashes, shapes', LINE_TEST, None),
        ('smooth shapes, tesselator, box shadow, svg', SMOOTH_EFFECTS_TEST, None),
        ('scissor, texture filters, wrap, blits, mipmaps', SCISSOR_TEXTURE_TEST, None),
        ('3d: depth test, custom vertex format', DEPTH_3D_TEST, {'DEPTH_MODE': 'quads'}),
        ('3d: Kivy\'s monkey example, normal matrix', DEPTH_3D_TEST, {'DEPTH_MODE': 'monkey'}),
    ]
    # Arguments pick tests by a word of their name.
    picked = [t for t in tests if not sys.argv[1:] or any(a in t[0] for a in sys.argv[1:])]
    results = [run(name, body, env) for name, body, env in picked]
    sys.exit(0 if all(results) else 1)
