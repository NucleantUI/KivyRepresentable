'''
Kivy's `nui` window and cgl backend against a host registered from Python.

Plays the part of the Swift host through ctypes: registers a KivyNUIHost
with libCKivyNUI, pushes events into its queue and ticks it, the way the
host's DisplaySync callback will. Each test runs in its own Python process,
because Kivy's window and GL backend are chosen once per process.

Needs `swift build --target CKivyNUI` and kivy2x built with USE_NUI=1 (see
kivy-notes.md). Run from the package root:

    python3 Tests/kivy/test_window_nui.py
'''

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KIVY = os.path.join(ROOT, 'kivy2x')
LIB = os.path.join(ROOT, '.build', 'debug', 'libCKivyNUI.dylib')


# The host side, shared by both child processes.
HOST = r'''
import ctypes, os, sys
sys.path.insert(0, KIVY)
lib = ctypes.CDLL(LIB)

class Metrics(ctypes.Structure):
    _fields_ = [('width', ctypes.c_int32), ('height', ctypes.c_int32),
                ('pixel_width', ctypes.c_int32), ('pixel_height', ctypes.c_int32),
                ('density', ctypes.c_float), ('dpi', ctypes.c_float)]

VOIDFN = ctypes.CFUNCTYPE(None, ctypes.c_void_p)
METRICSFN = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.POINTER(Metrics))
TITLEFN = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_char_p)
INTFN = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int)
BOOLFN = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_bool)

class Host(ctypes.Structure):
    _fields_ = [('context', ctypes.c_void_p), ('gl', ctypes.c_void_p),
                ('present', VOIDFN), ('get_window_metrics', METRICSFN),
                ('set_title', TITLEFN), ('set_system_cursor', INTFN),
                ('set_cursor_visible', BOOLFN), ('show_keyboard', VOIDFN),
                ('hide_keyboard', VOIDFN), ('request_close', VOIDFN)]

class Mouse(ctypes.Structure):
    _fields_ = [('x', ctypes.c_int32), ('y', ctypes.c_int32), ('button', ctypes.c_uint8)]

class Payload(ctypes.Union):
    _fields_ = [('mouse', Mouse), ('_size', ctypes.c_char * 32), ('_align', ctypes.c_int64)]

class Event(ctypes.Structure):
    _fields_ = [('type', ctypes.c_int), ('u', Payload)]

# kivy_nui.h KivyNUIEventType order.
QUIT, MOUSE_MOTION, MOUSE_BUTTON_DOWN, MOUSE_BUTTON_UP = 1, 2, 3, 4

seen = {'presents': 0, 'titles': [], 'closes': 0}
def _present(ctx): seen['presents'] += 1
def _metrics(ctx, out):
    out.contents.width, out.contents.height = 400, 300
    out.contents.pixel_width, out.contents.pixel_height = 800, 600
    out.contents.density, out.contents.dpi = 2.0, 192.0
def _title(ctx, utf8): seen['titles'].append(utf8.decode())
def _close(ctx): seen['closes'] += 1
def _noop(ctx, *a): pass

callbacks = [VOIDFN(_present), METRICSFN(_metrics), TITLEFN(_title),
             INTFN(_noop), BOOLFN(_noop), VOIDFN(_noop), VOIDFN(_noop),
             VOIDFN(_close)]
host = Host(None, GL_TABLE, *callbacks)
lib.kivy_nui_set_host(ctypes.byref(host))
lib.kivy_nui_tick.argtypes = [ctypes.c_double]

def push(type_, x=0, y=0, button=0):
    e = Event()
    e.type = type_
    e.u.mouse = Mouse(x, y, button)
    lib.kivy_nui_push_event(ctypes.byref(e))

def tick(n=1):
    for _ in range(n):
        lib.kivy_nui_tick(1 / 60.)
'''


WINDOW_TEST = r'''
os.environ['KIVY_WINDOW'] = 'nui'
os.environ['KIVY_GL_BACKEND'] = 'mock'   # no GL on the host yet
os.environ['KIVY_NO_ARGS'] = '1'
os.environ['KIVY_NO_CONFIG'] = '1'

from kivy.app import App
from kivy.uix.button import Button
from kivy.core.window import Window

assert type(Window).__name__ == 'WindowNUI', type(Window)
assert Window.system_size == [400, 300], Window.system_size
assert Window._density == 2.0, Window._density

presses = []

class Tapper(App):
    title = 'nui test'
    def build(self):
        b = Button(text='tap')
        b.bind(on_press=lambda *_: presses.append(1))
        return b

stopped = []
app = Tapper()
app.bind(on_stop=lambda *_: stopped.append(1))

# Returns right away: the host's ticks drive the loop from here.
app.run()
assert App.get_running_app() is app
tick(3)
assert seen['presents'] >= 1, seen
assert 'nui test' in seen['titles'], seen

# A click in the middle of the window, in SDL's top-left coordinates.
push(MOUSE_BUTTON_DOWN, 200, 150, 1)
push(MOUSE_BUTTON_UP, 200, 150, 1)
tick(3)
assert presses == [1], presses
# Kivy flipped y itself: 300 - 1 - 150 = 149 points, x2 density.
assert Window.mouse_pos == (400, 298), Window.mouse_pos

push(QUIT)
tick(2)
assert stopped == [1], stopped
assert seen['closes'] >= 1, seen
assert App.get_running_app() is None
# The tick is unregistered: more ticks reach nothing.
tick(2)
print('OK')
'''


GL_TEST = r'''
os.environ['KIVY_WINDOW'] = 'nui'
os.environ['KIVY_GL_BACKEND'] = 'nui'
os.environ['KIVY_NO_ARGS'] = '1'
os.environ['KIVY_NO_CONFIG'] = '1'

from kivy.graphics.cgl import cgl_init
cgl_init()

from kivy.graphics.opengl import glGetString, glClearColor, GL_VERSION
assert glGetString(GL_VERSION) == b'OpenGL ES 2.0 KivyRepresentable', glGetString(GL_VERSION)
glClearColor(0.25, 0.5, 0.75, 1.0)
assert clears == [(0.25, 0.5, 0.75, 1.0)], clears
print('OK')
'''


GL_TABLE = r'''
# KivyNUIGL: 129 function pointers; glGetString is member 0. glClearColor's
# index is looked up in the generated header so the test follows it.
import re
header = open(os.path.join(ROOT, 'dependencies', 'CKivyNUI', 'include', 'kivy_nui_gl.h')).read()
members = re.findall(r'\(\*(gl\w+)\)', header.split('typedef struct KivyNUIGL {')[1])
table = (ctypes.c_void_p * len(members))()

GETSTRING = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_uint)
version = ctypes.c_char_p(b'OpenGL ES 2.0 KivyRepresentable')
get_string = GETSTRING(lambda name: ctypes.cast(version, ctypes.c_void_p).value)
table[members.index('glGetString')] = ctypes.cast(get_string, ctypes.c_void_p)

CLEARCOLOR = ctypes.CFUNCTYPE(None, ctypes.c_float, ctypes.c_float, ctypes.c_float, ctypes.c_float)
clears = []
clear_color = CLEARCOLOR(lambda r, g, b, a: clears.append((r, g, b, a)))
table[members.index('glClearColor')] = ctypes.cast(clear_color, ctypes.c_void_p)
GL_TABLE = ctypes.cast(table, ctypes.c_void_p)
'''


def run(name, body, gl_table='GL_TABLE = None'):
    prelude = 'import ctypes, os, sys\n' + \
        'ROOT, KIVY, LIB = {!r}, {!r}, {!r}\n'.format(ROOT, KIVY, LIB)
    source = prelude + gl_table + '\n' + HOST + body
    # A real file, not `-c`: App.run() looks up the App class's source file
    # for its .kv.
    with tempfile.TemporaryDirectory() as tmp:
        script = os.path.join(tmp, 'nui_child.py')
        with open(script, 'w') as f:
            f.write(source)
        result = subprocess.run([sys.executable, script],
                                capture_output=True, text=True, timeout=120)
    ok = result.returncode == 0 and result.stdout.strip().endswith('OK')
    print('{} {}'.format('PASS' if ok else 'FAIL', name))
    if not ok:
        print(result.stdout[-3000:])
        print(result.stderr[-3000:])
    return ok


if __name__ == '__main__':
    results = [
        run('window: app runs from host ticks, click, quit', WINDOW_TEST),
        run('cgl_nui: Kivy GL calls reach the host table', GL_TEST, GL_TABLE),
    ]
    sys.exit(0 if all(results) else 1)
