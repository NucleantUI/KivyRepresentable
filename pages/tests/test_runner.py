'''
The web playground's runner (kivy_playground.runner) through the headless
host, as Tests/kivy/test_render_nui.py runs Kivy: the defaults run, then
edited sources run in their place in the same Python — a changed class and
changed rules showing, a broken app.py showing its error, a fixed one
running again.

Needs what test_render_nui.py needs (its HOST prelude is reused). From the
package root:

    KIVY_NUI_INSTALLED=1 python pages/tests/test_runner.py
'''

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'Tests', 'kivy'))
import test_render_nui as harness  # noqa: E402

SRC = os.path.join(os.path.dirname(HERE), 'python', 'src')

RUNNER_TEST = r'''
import sys, types, inspect
sys.path.insert(0, SRC)
from kivy_playground import runner
# As in the app: the page's reloads come in through the embedded Python,
# whose __main__ has no file.
sys.modules['__main__'] = types.ModuleType('__main__')

def shown():
    tick(6)
    return frame()

PY = """
import os
from kivy.app import App
from kivy.lang import Builder
from kivy.uix.widget import Widget

class Panel(Widget):
    def tint(self):
        return COLOR

class PlaygroundApp(App):
    def build(self):
        return Builder.load_file(os.path.join(os.path.dirname(__file__), "app.kv"))

if __name__ == "__main__":
    PlaygroundApp().run()
"""

KV = """
<Panel>:
    canvas:
        Color:
            rgba: self.tint()
        Rectangle:
            pos: self.pos
            size: self.size
Panel:
"""

KV_WITH_CHILD = KV.replace("Panel:\n", """Panel:
    Widget:
        pos: 0, 0
        size: 100, 100
        canvas:
            Color:
                rgba: 0, 1, 0, 1
            Rectangle:
                pos: self.pos
                size: self.size
""")

# Edits sent before Kivy started are what it starts with.
runner.reload(PY.replace("COLOR", "(1, 0, 0, 1)"), KV)
runner.main()
data = shown()
save(data, 'playground_runner_1')
assert pixel(data, 200, 200) == (255, 0, 0, 255), pixel(data, 200, 200)

# The class and the rules both changed: the new ones build the widgets.
runner.reload(PY.replace("COLOR", "(0, 0, 1, 1)"), KV_WITH_CHILD)
data = shown()
save(data, 'playground_runner_2')
assert pixel(data, 200, 200) == (0, 0, 255, 255), pixel(data, 200, 200)
assert pixel(data, 50, 50) == (0, 255, 0, 255), pixel(data, 50, 50)
from kivy.factory import Factory
from kivy.core.window import Window
assert Factory.Panel is type(Window.children[0]), (Factory.Panel, Window.children)
assert len(Window.children) == 1, Window.children
from kivy.app import App
assert inspect.getfile(type(App.get_running_app())) == runner.APP_PY

# A broken app.py: its traceback, in the window.
runner.reload("raise ValueError('broken on purpose')", KV)
data = shown()
save(data, 'playground_runner_error')
label = Window.children[0]
assert 'broken on purpose' in label.text, label.text
assert pixel(data, 200, 200) != (0, 0, 255, 255), pixel(data, 200, 200)

# Fixed again: it runs, and the error is gone. Kivy's classes app.py
# imported (Widget, used by the kv) are still Factory's after the reloads.
runner.reload(PY.replace("COLOR", "(1, 1, 0, 1)"), KV_WITH_CHILD)
data = shown()
save(data, 'playground_runner_3')
assert pixel(data, 200, 200) == (255, 255, 0, 255), pixel(data, 200, 200)
assert pixel(data, 50, 50) == (0, 255, 0, 255), pixel(data, 50, 50)
assert len(Window.children) == 1 and type(Window.children[0]).__name__ == 'Panel', Window.children
runner.reload(PY.replace("COLOR", "(1, 1, 0, 1)"), KV_WITH_CHILD)
data = shown()
assert pixel(data, 50, 50) == (0, 255, 0, 255), pixel(data, 50, 50)
from kivy.uix.widget import Widget
assert Factory.Widget is Widget
print('OK')
'''


DEFAULTS_TEST = r'''
import sys
sys.path.insert(0, SRC)
from kivy_playground import runner

# The app the page opens with.
runner.main()
tick(6)
data = frame()
save(data, 'playground_runner_defaults')
from kivy.core.window import Window
root = Window.children[0]
assert type(root).__name__ == 'IntroScreen', root
assert root.ids.action_btn.text == 'Get Started'
root.on_button_click()
assert root.ids.action_btn.text == 'Ready to Build!'
assert near(pixel(data, 5, 5), (26, 28, 33, 255), 2), pixel(data, 5, 5)  # the kv's background
print('OK')
'''


if __name__ == '__main__':
    tests = [
        ('runner: edits run in place of the last run, errors show', RUNNER_TEST),
        ('runner: the default app', DEFAULTS_TEST),
    ]
    results = [harness.run(name, 'SRC = {!r}\n'.format(SRC) + body) for name, body in tests]
    sys.exit(0 if all(results) else 1)
