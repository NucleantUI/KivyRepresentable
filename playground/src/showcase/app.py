"""
A tour of Kivy, enough of it to show the nui backend holds up: a
ScreenManager with slide, fade and wipe transitions (the last two are
Kivy's shader transitions — Fbos and custom GLSL), layouts, widgets, a
scroll view, clock-driven canvas drawing, animations and a custom
fragment shader.

SHOWCASE_TOUR=<seconds> walks through the screens on its own.
"""

import os
import time
from math import cos, pi, sin

from kivy.animation import Animation
from kivy.app import App
from kivy.clock import Clock
from kivy.core.window import Window
from kivy.graphics import (
    Bezier, BoxShadow, Color, Ellipse, Line, Mesh, PopMatrix, PushMatrix,
    Rectangle, RenderContext, Rotate, StencilPop, StencilPush, StencilUnUse,
    StencilUse, Translate,
)
from kivy.properties import NumericProperty, StringProperty
from kivy.uix.screenmanager import (
    FadeTransition, Screen, ScreenManager, SlideTransition, WipeTransition,
)
from kivy.uix.widget import Widget


SCREENS = ["home", "canvas", "clock", "widgets", "shader"]


# MARK: - Canvas screen

class OrbitCanvas(Widget):
    """Redrawn from the clock every frame: rotating rings and a fan star,
    planets on orbits, a Bezier, pies, and stripes clipped by a stencil
    circle."""

    angle = NumericProperty(0)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._event = None

    def start(self):
        if self._event is None:
            self._event = Clock.schedule_interval(self._step, 1 / 60.)

    def stop(self):
        if self._event is not None:
            self._event.cancel()
            self._event = None

    def _step(self, dt):
        self.angle = (self.angle + 60 * dt) % 360
        self.draw()

    def draw(self):
        cx, cy = self.center
        radius = min(self.width, self.height) * 0.42
        a = self.angle
        self.canvas.clear()
        with self.canvas:
            # Rings and a star turning around the middle.
            PushMatrix()
            Translate(cx, cy)
            Rotate(angle=a, origin=(0, 0))
            for i, scale in enumerate((1.0, 0.8, 0.6)):
                Color(0.2 + 0.25 * i, 0.6, 1 - 0.3 * i, 1)
                sides = 6 + 2 * i
                points = []
                for k in range(sides):
                    t = 2 * pi * k / sides
                    points += [cos(t) * radius * scale, sin(t) * radius * scale]
                Line(points=points, close=True, width=2)
            Color(1, 0.8, 0.2, 1)
            star = [0, 0, 0, 0]
            for k in range(11):
                t = 2 * pi * k / 10
                r = radius * (0.35 if k % 2 else 0.15)
                star += [cos(t) * r, sin(t) * r, 0, 0]
            Mesh(vertices=star, indices=list(range(12)), mode='triangle_fan')
            PopMatrix()

            # Planets on their orbits.
            for i, (orbit, speed, color) in enumerate((
                    (0.55, 1.0, (1, 0.3, 0.3)),
                    (0.75, -0.6, (0.3, 1, 0.5)),
                    (0.95, 0.35, (0.7, 0.5, 1)))):
                t = (a * speed + i * 120) * pi / 180
                px = cx + cos(t) * radius * orbit
                py = cy + sin(t) * radius * orbit
                Color(*color, 1)
                Ellipse(pos=(px - 10, py - 10), size=(20, 20))
                Color(*color, 0.3)
                Line(circle=(cx, cy, radius * orbit), width=1)

            # A wave along the bottom.
            Color(0.4, 0.9, 1, 1)
            x0 = self.x + 20
            y0 = self.y + 40
            w = self.width - 40
            phase = a * pi / 90
            Bezier(points=[x0, y0, x0 + w * 0.33, y0 + 60 * sin(phase),
                           x0 + w * 0.66, y0 - 60 * sin(phase), x0 + w, y0],
                   segments=80)

            # Pies with moving gaps, top left.
            for i in range(3):
                Color(1, 0.5 + 0.2 * i, 0.3, 1)
                start = (a * (i + 1)) % 360
                Ellipse(pos=(self.x + 20 + i * 70, self.top - 80), size=(60, 60),
                        angle_start=start, angle_end=start + 270)

            # Stripes clipped by a circle, top right.
            sx, sy, sr = self.right - 90, self.top - 90, 60
            StencilPush()
            Ellipse(pos=(sx - sr, sy - sr), size=(2 * sr, 2 * sr))
            StencilUse()
            for k in range(-6, 7):
                Color(1, 1, 1, 1) if k % 2 else Color(0.9, 0.2, 0.4, 1)
                offset = (a % 20) + k * 20
                Rectangle(pos=(sx - sr + offset, sy - sr), size=(10, 2 * sr))
            StencilUnUse()
            Ellipse(pos=(sx - sr, sy - sr), size=(2 * sr, 2 * sr))
            StencilPop()


# MARK: - Shader screen

PLASMA = '''
$HEADER$
uniform vec2 resolution;
uniform float time;

void main(void) {
    vec2 p = gl_FragCoord.xy / resolution.xy;
    float x = p.x * 10.0;
    float y = p.y * 10.0;
    float v = sin(x + time);
    v += sin((y + time) / 2.0);
    v += sin((x + y + time) / 2.0);
    float cx = x + 0.5 * sin(time / 5.0) * 10.0;
    float cy = y + 0.5 * cos(time / 3.0) * 10.0;
    v += sin(sqrt(cx * cx + cy * cy + 1.0) + time);
    v = v / 2.0;
    vec3 col = vec3(sin(v * 3.14159), sin(v * 3.14159 + 2.094), sin(v * 3.14159 + 4.188));
    gl_FragColor = vec4(col * 0.5 + 0.5, 1.0);
}
'''


class PlasmaView(Widget):
    """A Rectangle drawn by a fragment shader of the app's own, its
    uniforms set from the clock."""

    def __init__(self, **kwargs):
        self.canvas = RenderContext(use_parent_projection=True,
                                    use_parent_modelview=True,
                                    use_parent_frag_modelview=True)
        self.canvas.shader.fs = PLASMA
        super().__init__(**kwargs)
        with self.canvas:
            self.rect = Rectangle(pos=self.pos, size=self.size)
        self.bind(pos=self._layout, size=self._layout)
        self._event = None

    def _layout(self, *_):
        self.rect.pos = self.pos
        self.rect.size = self.size

    def start(self):
        if self._event is None:
            self._event = Clock.schedule_interval(self._step, 1 / 60.)

    def stop(self):
        if self._event is not None:
            self._event.cancel()
            self._event = None

    def _step(self, dt):
        self.canvas['time'] = Clock.get_boottime()
        # gl_FragCoord is in window pixels, as Window.size is.
        self.canvas['resolution'] = [float(Window.width), float(Window.height)]


# MARK: - Screens

class HomeScreen(Screen):
    pass


class CanvasScreen(Screen):
    def on_enter(self):
        self.ids.orbit.start()

    def on_leave(self):
        self.ids.orbit.stop()


class ClockScreen(Screen):
    ticks = NumericProperty(0)
    elapsed = NumericProperty(0)
    once_status = StringProperty('schedule_once: waiting…')

    def on_enter(self):
        self.ticks = 0
        self.elapsed = 0
        self.once_status = 'schedule_once: waiting…'
        self._interval = Clock.schedule_interval(self._tick, 0.1)
        self._once = Clock.schedule_once(self._fired, 1.5)
        self._animate()

    def on_leave(self):
        self._interval.cancel()
        self._once.cancel()
        Animation.cancel_all(self.ids.ball)
        Animation.cancel_all(self.ids.progress)

    def _tick(self, dt):
        self.ticks += 1
        self.elapsed += dt

    def _fired(self, dt):
        self.once_status = 'schedule_once: fired after {:.2f}s'.format(self.elapsed)

    def _animate(self):
        ball = self.ids.ball
        track = self.ids.track
        ball.pos = (track.x, track.center_y - ball.height / 2)
        hop = (Animation(x=track.right - ball.width, duration=1.2, t='in_out_quad')
               + Animation(x=track.x, duration=1.2, t='out_bounce'))
        hop.repeat = True
        hop.start(ball)
        progress = self.ids.progress
        progress.value = 0
        fill = Animation(value=100, duration=3) + Animation(value=0, duration=0.4)
        fill.repeat = True
        fill.start(progress)


class WidgetsScreen(Screen):
    def on_kv_post(self, base_widget):
        from kivy.uix.button import Button
        rows = self.ids.rows
        for i in range(60):
            rows.add_widget(Button(text='Row {}'.format(i + 1), size_hint_y=None, height=36))


class ShaderScreen(Screen):
    def on_enter(self):
        self.ids.plasma.start()

    def on_leave(self):
        self.ids.plasma.stop()


# MARK: - App

class ShowcaseApp(App):
    title = 'Kivy on Nucleant'
    clock_text = StringProperty('')
    fps_text = StringProperty('')

    def build(self):
        # showcase.kv is loaded by Kivy itself: ShowcaseApp -> showcase.kv.
        self.manager = ScreenManager()
        for screen in (HomeScreen(name='home'), CanvasScreen(name='canvas'),
                       ClockScreen(name='clock'), WidgetsScreen(name='widgets'),
                       ShaderScreen(name='shader')):
            self.manager.add_widget(screen)
        Clock.schedule_interval(self._status, 0.5)
        self._status(0)
        tour = os.environ.get('SHOWCASE_TOUR')
        if tour:
            Clock.schedule_interval(self._next, float(tour))
        return self.manager

    def _status(self, dt):
        self.clock_text = time.strftime('%H:%M:%S')
        self.fps_text = '{:.0f} fps'.format(Clock.get_fps())

    def go(self, name):
        """Each screen is reached with a different transition."""
        if name == 'home':
            self.manager.transition = SlideTransition(direction='right')
        elif name == 'shader':
            self.manager.transition = WipeTransition()
        elif name == 'clock':
            self.manager.transition = FadeTransition()
        else:
            self.manager.transition = SlideTransition(direction='left')
        self.manager.current = name

    def _next(self, dt):
        index = SCREENS.index(self.manager.current)
        self.go(SCREENS[(index + 1) % len(SCREENS)])


def main():
    ShowcaseApp().run()
