'''
The playground's Kivy app: `app.py` and `app.kv` as the page's editors hold
them, written to a folder and `app.py` run as `__main__` with fresh globals,
as `python app.py` would. When they change, the running app is stopped and
the new ones run in its place, in the same Python:

  - Kivy's stop (`App.stop`) ends the loop and empties the window; the
    window's tick, which the stop takes off the host, is put back;
  - the classes the last run defined leave Factory, which keeps the first class it is
    given by a name, and its rules leave Builder (`unload_file`), so the
    new `app.py` and `app.kv` are what builds the widgets;
  - each run is a module of its own, `sys.modules['__main__']` while it
    runs, its `__file__` app.py: Kivy finds an app's files from its class's
    module (`App.load_kv`, `App.directory`).

An error running them shows its traceback in the window.
'''

import builtins
import os
import sys
import tempfile
import traceback
import types

FOLDER = os.path.join(tempfile.gettempdir(), 'kivy_playground')
APP_PY = os.path.join(FOLDER, 'app.py')
APP_KV = os.path.join(FOLDER, 'app.kv')
DEFAULTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'default')

_started = False
_pending = None
_last_globals = None


def defaults():
    '''The app the playground opens with: default/app.py and default/app.kv.'''
    with open(os.path.join(DEFAULTS, 'app.py')) as py, open(os.path.join(DEFAULTS, 'app.kv')) as kv:
        return py.read(), kv.read()


def main():
    '''Runs the sources the page sent before Kivy started, else the defaults.'''
    global _started
    _started = True
    run(*(_pending or defaults()))


def reload(py, kv):
    '''The editors changed: run these in place of what runs. Before `main`
    (Kivy not started yet), they are kept for it.'''
    global _pending
    if not _started:
        _pending = (py, kv)
        return
    run(py, kv)


def run(py, kv):
    global _last_globals
    _stop_last()
    os.makedirs(FOLDER, exist_ok=True)
    with open(APP_PY, 'w') as f:
        f.write(py)
    with open(APP_KV, 'w') as f:
        f.write(kv)
    module = types.ModuleType('__main__')
    module.__file__ = APP_PY
    module.__builtins__ = builtins
    sys.modules['__main__'] = module
    _last_globals = module.__dict__
    try:
        exec(compile(py, APP_PY, 'exec'), module.__dict__)
    except BaseException:
        traceback.print_exc()
        _show_error(traceback.format_exc())


def _stop_last():
    '''What the last run left: its app stopped, its classes and rules gone,
    the window's tick back on the host.'''
    if _last_globals is None:
        return
    from kivy.app import App
    from kivy.base import EventLoop, stopTouchApp
    from kivy.core.window import Window
    from kivy.factory import Factory
    from kivy.lang import Builder

    app = App.get_running_app()
    if app:
        app.stop()
    else:
        stopTouchApp()
    for child in list(Window.children):
        Window.remove_widget(child)
    Builder.unload_file(APP_KV)
    # The classes app.py defined — not Kivy's own it imported.
    for name, value in _last_globals.items():
        if isinstance(value, type) and value.__module__ == '__main__' \
                and Factory.classes.get(name, {}).get('cls') is value:
            Factory.unregister(name)
    Window._win.set_tick(Window._tick)


def _show_error(text):
    '''The traceback, in the window, until the next run.'''
    from kivy.app import App
    from kivy.base import stopTouchApp
    from kivy.uix.label import Label

    app = App.get_running_app()
    if app:
        app.stop()
    else:
        stopTouchApp()

    class PlaygroundError(App):
        def build(self):
            label = Label(text=text, color=(1, 0.45, 0.45, 1), font_size='13sp',
                          halign='left', valign='top', padding=(16, 16))
            label.bind(size=lambda widget, size: setattr(widget, 'text_size', size))
            return label

    PlaygroundError().run()
