'''
NUI Window
==========

Windowing provider for Kivy hosted by a KivyRepresentable app (Swift, on
NucleantVulkan). The host owns the real window, the GPU and the display
sync; it registers itself with the shared C api (kivy_nui.h) and starts
Python. This window then:

* renders through the `nui` cgl backend (graphics/cgl_backend/cgl_nui.pyx)
  into the image the host's shader node draws, and calls the host's
  `present` on flip;
* reads input from the host's queue, which delivers what SDL did, in SDL's
  shape and coordinates — so the event handling below is WindowSDL's;
* has no loop of its own: the host ticks it once per display-sync frame,
  and each tick runs one pass of what `EventLoop.mainloop` ran
  (`EventLoop.idle()`, then `mainloop()` here for the events). `App.run()`
  and `runTouchApp()` return instead of looping (`ticked_by_host`).

Run with ``KIVY_WINDOW=nui`` and ``KIVY_GL_BACKEND=nui``, set by the host
before it starts Python.
'''

__all__ = ('WindowNUI', )

import sys
from kivy.logger import Logger
from kivy.base import EventLoop, ExceptionManager, stopTouchApp
from kivy.clock import Clock
from kivy.config import Config
from kivy.core.window import WindowBase
try:
    from kivy.core.window._window_nui import _WindowNUIStorage, is_hosted
except ImportError:
    from kivy.core import handle_win_lib_import_error
    handle_win_lib_import_error(
        'window', 'nui', 'kivy.core.window._window_nui')
    raise
from kivy.input.provider import MotionEventProvider
from kivy.input.motionevent import MotionEvent
from kivy.utils import platform
from kivy.compat import unichr
from collections import deque


# Key codes and modifiers arrive as SDL2's (kivy_nui.h), so these are
# window_sdl2.py's, unchanged.
# SDL_keycode.h, https://wiki.libsdl.org/SDL_Keymod
KMOD_NONE = 0x0000
KMOD_LSHIFT = 0x0001
KMOD_RSHIFT = 0x0002
KMOD_LCTRL = 0x0040
KMOD_RCTRL = 0x0080
KMOD_LALT = 0x0100
KMOD_RALT = 0x0200
KMOD_LGUI = 0x0400
KMOD_RGUI = 0x0800
KMOD_NUM = 0x1000
KMOD_CAPS = 0x2000
KMOD_MODE = 0x4000

SDLK_SHIFTL = 1073742049
SDLK_SHIFTR = 1073742053
SDLK_LCTRL = 1073742048
SDLK_RCTRL = 1073742052
SDLK_LALT = 1073742050
SDLK_RALT = 1073742054
SDLK_LEFT = 1073741904
SDLK_RIGHT = 1073741903
SDLK_UP = 1073741906
SDLK_DOWN = 1073741905
SDLK_HOME = 1073741898
SDLK_END = 1073741901
SDLK_PAGEUP = 1073741899
SDLK_PAGEDOWN = 1073741902
SDLK_SUPER = 1073742051
SDLK_CAPS = 1073741881
SDLK_INSERT = 1073741897
SDLK_KEYPADNUM = 1073741907
SDLK_KP_DIVIDE = 1073741908
SDLK_KP_MULTIPLY = 1073741909
SDLK_KP_MINUS = 1073741910
SDLK_KP_PLUS = 1073741911
SDLK_KP_ENTER = 1073741912
SDLK_KP_1 = 1073741913
SDLK_KP_2 = 1073741914
SDLK_KP_3 = 1073741915
SDLK_KP_4 = 1073741916
SDLK_KP_5 = 1073741917
SDLK_KP_6 = 1073741918
SDLK_KP_7 = 1073741919
SDLK_KP_8 = 1073741920
SDLK_KP_9 = 1073741921
SDLK_KP_0 = 1073741922
SDLK_KP_DOT = 1073741923
SDLK_F1 = 1073741882
SDLK_F2 = 1073741883
SDLK_F3 = 1073741884
SDLK_F4 = 1073741885
SDLK_F5 = 1073741886
SDLK_F6 = 1073741887
SDLK_F7 = 1073741888
SDLK_F8 = 1073741889
SDLK_F9 = 1073741890
SDLK_F10 = 1073741891
SDLK_F11 = 1073741892
SDLK_F12 = 1073741893
SDLK_F13 = 1073741894
SDLK_F14 = 1073741895
SDLK_F15 = 1073741896


class NUIMotionEvent(MotionEvent):

    def __init__(self, *args, **kwargs):
        kwargs.setdefault('is_touch', True)
        kwargs.setdefault('type_id', 'touch')
        super().__init__(*args, **kwargs)
        self.profile = ('pos', 'pressure')

    def depack(self, args):
        self.sx, self.sy, self.pressure = args
        super().depack(args)


class NUIMotionEventProvider(MotionEventProvider):
    '''SDL2MotionEventProvider for the host's finger events: normalized,
    top-left, flipped here exactly as SDL's were.'''
    win = None
    q = deque()
    touchmap = {}

    def update(self, dispatch_fn):
        touchmap = self.touchmap
        while True:
            try:
                value = self.q.pop()
            except IndexError:
                return

            action, fid, x, y, pressure = value
            y = 1 - y
            if fid not in touchmap:
                touchmap[fid] = me = NUIMotionEvent(
                    'nui', fid, (x, y, pressure)
                )
            else:
                me = touchmap[fid]
                me.move((x, y, pressure))
            if action == 'fingerdown':
                dispatch_fn('begin', me)
            elif action == 'fingerup':
                me.update_time_end()
                dispatch_fn('end', me)
                del touchmap[fid]
            else:
                dispatch_fn('update', me)


class WindowNUI(WindowBase):

    #: The host ticks the event loop; `App.run()` / `runTouchApp()` must
    #: return instead of running `EventLoop.mainloop()`.
    ticked_by_host = True

    _do_resize_ev = None

    managed_textinput = True

    def __init__(self, **kwargs):
        if not is_hosted():
            # Lets core_select_lib fall through to the next window provider.
            raise Exception(
                'WindowNUI: no KivyRepresentable host has registered '
                '(kivy_nui_set_host)')
        self._pause_loop = False
        self._cursor_entered = False
        self._drop_pos = None
        self._raw_mouse = (0, 0)
        self._nui_keyboard = None
        self._win = _WindowNUIStorage()
        super(WindowNUI, self).__init__()
        self._mouse_x = self._mouse_y = -1
        self._meta_keys = (
            KMOD_LCTRL, KMOD_RCTRL, KMOD_RSHIFT,
            KMOD_LSHIFT, KMOD_RALT, KMOD_LALT, KMOD_LGUI,
            KMOD_RGUI, KMOD_NUM, KMOD_CAPS, KMOD_MODE)
        self.command_keys = {
                    27: 'escape',
                    9: 'tab',
                    8: 'backspace',
                    13: 'enter',
                    127: 'del',
                    271: 'enter',
                    273: 'up',
                    274: 'down',
                    275: 'right',
                    276: 'left',
                    278: 'home',
                    279: 'end',
                    280: 'pgup',
                    281: 'pgdown'}
        self._mouse_buttons_down = set()
        self.key_map = {SDLK_LEFT: 276, SDLK_RIGHT: 275, SDLK_UP: 273,
                        SDLK_DOWN: 274, SDLK_HOME: 278, SDLK_END: 279,
                        SDLK_PAGEDOWN: 281, SDLK_PAGEUP: 280, SDLK_SHIFTR: 303,
                        SDLK_SHIFTL: 304, SDLK_SUPER: 309, SDLK_LCTRL: 305,
                        SDLK_RCTRL: 306, SDLK_LALT: 308, SDLK_RALT: 307,
                        SDLK_CAPS: 301, SDLK_INSERT: 277, SDLK_F1: 282,
                        SDLK_F2: 283, SDLK_F3: 284, SDLK_F4: 285, SDLK_F5: 286,
                        SDLK_F6: 287, SDLK_F7: 288, SDLK_F8: 289, SDLK_F9: 290,
                        SDLK_F10: 291, SDLK_F11: 292, SDLK_F12: 293,
                        SDLK_F13: 294, SDLK_F14: 295, SDLK_F15: 296,
                        SDLK_KEYPADNUM: 300, SDLK_KP_DIVIDE: 267,
                        SDLK_KP_MULTIPLY: 268, SDLK_KP_MINUS: 269,
                        SDLK_KP_PLUS: 270, SDLK_KP_ENTER: 271,
                        SDLK_KP_DOT: 266, SDLK_KP_0: 256, SDLK_KP_1: 257,
                        SDLK_KP_2: 258, SDLK_KP_3: 259, SDLK_KP_4: 260,
                        SDLK_KP_5: 261, SDLK_KP_6: 262, SDLK_KP_7: 263,
                        SDLK_KP_8: 264, SDLK_KP_9: 265}
        if platform == 'ios':
            # XXX ios keyboard suck, when backspace is hit, the delete
            # keycode is sent. fix it.
            self.key_map[127] = 8
        elif platform == 'android':
            # map android back button to escape
            self.key_map[1073742094] = 27

    def create_window(self, *largs):
        if not self.initialized:
            # The host decides the window's size; Kivy follows it.
            w, h = self._win.window_size
            self.system_size = (w, h)
            self._update_density_and_dpi()
            self._pos = (0, 0)

        super(WindowNUI, self).create_window()
        self._set_cursor_state(self.show_cursor)

        if self.initialized:
            return

        Logger.info('Window: auto add nui input provider')
        NUIMotionEventProvider.win = self
        EventLoop.add_input_provider(NUIMotionEventProvider('nui', ''))

        self._win.set_tick(self._tick)

    def _update_density_and_dpi(self):
        _, _, pixel_width, _, density, dpi = self._win.window_metrics()
        self._density = density or (pixel_width / self._size[0])
        if self._is_desktop:
            self.dpi = dpi or self._density * 96.

    # MARK: - Driven by the host

    def _tick(self, dt):
        '''One display-sync frame: one pass of `EventLoop.mainloop`.'''
        if EventLoop.status == 'idle':
            # The window exists from import on; the loop starts with
            # App.run() / runTouchApp(). Nothing to run until then.
            return
        try:
            if self._pause_loop:
                # Paused (app in background / minimized): only listen for
                # what ends the pause, as WindowSDL's wait_event loop did.
                self.mainloop()
            elif not EventLoop.quit and EventLoop.status == 'started':
                EventLoop.idle()
                self.mainloop()
        except BaseException as inst:
            r = ExceptionManager.handle_exception(inst)
            if r == ExceptionManager.RAISE:
                Logger.exception('WindowNUI: Exception in the tick, stopping')
                self._finish()
                return

        if EventLoop.quit or EventLoop.status != 'started':
            self._finish()

    def _finish(self):
        '''What `runTouchApp` and `App.run` do once `EventLoop.mainloop`
        returns: stop the loop, then the app.'''
        from kivy.app import App
        self._win.set_tick(None)
        stopTouchApp()
        app = App.get_running_app()
        if app:
            app._stop()
        # With SDL the process ended here; the host lives on, so tell it.
        self._win.request_close()

    def close(self):
        self._win.set_tick(None)
        super(WindowNUI, self).close()
        self.initialized = False
        self._win.request_close()

    # MARK: - Window

    def set_title(self, title):
        self._win.set_window_title(title)

    def flip(self):
        self._win.flip()
        super(WindowNUI, self).flip()

    def set_system_cursor(self, cursor_name):
        return self._win.set_system_cursor(cursor_name)

    def _set_cursor_state(self, value):
        self._win._set_cursor_state(value)

    def _fix_mouse_pos(self, x, y):
        self._raw_mouse = (x, y)
        self.mouse_pos = (
            x * self._density,
            (self.system_size[1] - 1 - y) * self._density
        )
        return x, y

    # MARK: - Events

    def _event_filter(self, action, *largs):
        '''WindowSDL._event_filter. SDL called it from its event watch; here
        the app events come through the queue like the rest.'''
        from kivy.app import App
        if action == 'app_terminating':
            EventLoop.quit = True

        elif action == 'app_lowmemory':
            self.dispatch('on_memorywarning')

        elif action == 'app_willenterbackground':
            app = App.get_running_app()
            if not app:
                Logger.info('WindowNUI: No running App found, pause.')

            elif not app.dispatch('on_pause'):
                Logger.info(
                    'WindowNUI: App doesn\'t support pause mode, stop.')
                stopTouchApp()
                return

            self._pause_loop = True

        elif action == 'app_didenterforeground':
            if self._pause_loop:
                self._pause_loop = False
                app = App.get_running_app()
                if app:
                    app.dispatch('on_resume')

    def mainloop(self):
        while True:
            event = self._win.poll()
            if event is False:
                break
            if event is None:
                continue

            action, args = event[0], event[1:]

            if action.startswith('app_'):
                self._event_filter(action, *args)
                continue

            if self._pause_loop:
                # WindowSDL's pause loop: drops still go through, a resize
                # or restore of a minimized window ends the pause, the rest
                # waits.
                if action.startswith('drop'):
                    self._dispatch_drop_event(action, args)
                elif action in ('windowrestored', 'app_willenterforeground'):
                    self._resume()
                elif action == 'quit':
                    EventLoop.quit = True
                    break
                continue

            if action == 'quit':
                if self.dispatch('on_request_close'):
                    continue
                EventLoop.quit = True
                break

            elif action in ('fingermotion', 'fingerdown', 'fingerup'):
                # WindowSDL only took fingers on ios/android because SDL also
                # sent them for the trackpad on desktop; the host sends real
                # touches only.
                NUIMotionEventProvider.q.appendleft(event)

            elif action == 'mousemotion':
                x, y = args
                x, y = self._fix_mouse_pos(x, y)
                self._mouse_x = x
                self._mouse_y = y
                if not self._cursor_entered:
                    self._cursor_entered = True
                    self.dispatch('on_cursor_enter')
                # don't dispatch motion if no button are pressed
                if len(self._mouse_buttons_down) == 0:
                    continue
                self._mouse_meta = self.modifiers
                self.dispatch('on_mouse_move', x, y, self.modifiers)

            elif action in ('mousebuttondown', 'mousebuttonup'):
                x, y, button = args
                x, y = self._fix_mouse_pos(x, y)
                self._mouse_x = x
                self._mouse_y = y
                if not self._cursor_entered:
                    self._cursor_entered = True
                    self.dispatch('on_cursor_enter')
                btn = 'left'
                if button == 3:
                    btn = 'right'
                elif button == 2:
                    btn = 'middle'
                elif button == 4:
                    btn = "mouse4"
                elif button == 5:
                    btn = "mouse5"
                eventname = 'on_mouse_down'
                self._mouse_buttons_down.add(button)
                if action == 'mousebuttonup':
                    eventname = 'on_mouse_up'
                    self._mouse_buttons_down.discard(button)
                self.dispatch(eventname, x, y, btn, self.modifiers)

            elif action.startswith('mousewheel'):
                x, y, button, mouse_x, mouse_y = args
                if not self._collide_and_dispatch_cursor_enter(
                        mouse_x, mouse_y):
                    continue
                btn = 'scrolldown'
                if action.endswith('up'):
                    btn = 'scrollup'
                elif action.endswith('right'):
                    btn = 'scrollright'
                elif action.endswith('left'):
                    btn = 'scrollleft'

                self._mouse_meta = self.modifiers
                self._mouse_btn = btn
                self._mouse_down = True
                self.dispatch('on_mouse_down',
                    self._mouse_x, self._mouse_y, btn, self.modifiers)
                self._mouse_down = False
                self.dispatch('on_mouse_up',
                    self._mouse_x, self._mouse_y, btn, self.modifiers)

            elif action.startswith('drop'):
                self._dispatch_drop_event(action, args)

            elif action == 'windowresized':
                # The host resized its image already; follow it.
                self._size = self._win.window_size
                ev = self._do_resize_ev
                if ev is None:
                    ev = Clock.schedule_once(self._do_resize, .1)
                    self._do_resize_ev = ev
                else:
                    ev()

            elif action == 'windowdisplaychanged':
                self._update_density_and_dpi()

            elif action == 'windowmoved':
                self.dispatch('on_move')

            elif action == 'windowrestored':
                self.dispatch('on_restore')
                self.canvas.ask_update()

            elif action == 'windowexposed':
                self.canvas.ask_update()

            elif action == 'windowminimized':
                self.dispatch('on_minimize')
                if Config.getboolean('kivy', 'pause_on_minimize'):
                    self.do_pause()

            elif action == 'windowmaximized':
                self.dispatch('on_maximize')

            elif action == 'windowhidden':
                self.dispatch('on_hide')

            elif action == 'windowshown':
                self.dispatch('on_show')

            elif action == 'windowfocusgained':
                self._focus = True

            elif action == 'windowfocuslost':
                self._focus = False

            elif action == 'windowenter':
                self._collide_and_dispatch_cursor_enter(*self._raw_mouse)

            elif action == 'windowleave':
                self._cursor_entered = False
                self.dispatch('on_cursor_leave')

            elif action in ('keydown', 'keyup'):
                mod, key, scancode, kstr = args

                try:
                    key = self.key_map[key]
                except KeyError:
                    pass

                if action == 'keydown':
                    self._update_modifiers(mod, key)
                else:
                    # ignore the key, it has been released
                    self._update_modifiers(mod)

                if (key not in self._modifiers and
                        key not in self.command_keys.keys()):
                    try:
                        kstr_chr = unichr(key)
                        try:
                            encoding = getattr(sys.stdout, 'encoding',
                                               'utf8') or 'utf8'
                            kstr_chr.encode(encoding)
                            kstr = kstr_chr
                        except UnicodeError:
                            pass
                    except ValueError:
                        pass

                if action == 'keyup':
                    self.dispatch('on_key_up', key, scancode)
                    continue

                # don't dispatch more key if down event is accepted
                if self.dispatch('on_key_down', key,
                                 scancode, kstr,
                                 self.modifiers):
                    continue
                self.dispatch('on_keyboard', key,
                              scancode, kstr,
                              self.modifiers)

            elif action == 'textinput':
                text = args[0]
                self.dispatch('on_textinput', text)

            elif action == 'textedit':
                text = args[0]
                self.dispatch('on_textedit', text)

            else:
                Logger.trace('WindowNUI: Unhandled event %s' % str(event))

    def _dispatch_drop_event(self, action, args):
        x, y = (0, 0) if self._drop_pos is None else self._drop_pos
        if action == 'dropfile':
            self.dispatch('on_drop_file', args[0], x, y)
        elif action == 'droptext':
            self.dispatch('on_drop_text', args[0], x, y)
        elif action == 'dropbegin':
            self._drop_pos = x, y = args
            self._collide_and_dispatch_cursor_enter(x, y)
            self.dispatch('on_drop_begin', x, y)
        elif action == 'dropend':
            self._drop_pos = None
            self.dispatch('on_drop_end', x, y)

    def _collide_and_dispatch_cursor_enter(self, x, y):
        # x, y are relative to window left/top position
        w, h = self._win.window_size
        if 0 <= x < w and 0 <= y < h:
            self._mouse_x, self._mouse_y = self._fix_mouse_pos(x, y)
            if not self._cursor_entered:
                self._cursor_entered = True
                self.dispatch('on_cursor_enter')
            return True

    def _do_resize(self, dt):
        Logger.debug('Window: Resize window to %s' % str(self.size))
        self.dispatch('on_pre_resize', *self.size)

    def do_pause(self):
        # WindowSDL blocked here polling until a resume event; the host
        # keeps ticking instead, and mainloop ends the pause (_resume).
        from kivy.app import App
        app = App.get_running_app()
        if not app:
            Logger.info('WindowNUI: No running App found, pause.')
        elif not app.dispatch('on_pause'):
            Logger.info('WindowNUI: App doesn\'t support pause mode, stop.')
            stopTouchApp()
            return
        self._pause_loop = True

    def _resume(self):
        from kivy.app import App
        self._pause_loop = False
        app = App.get_running_app()
        if app:
            app.dispatch('on_resume')

    def _update_modifiers(self, mods=None, key=None):
        if mods is None and key is None:
            return
        modifiers = set()

        if mods is not None:
            if mods & (KMOD_RSHIFT | KMOD_LSHIFT):
                modifiers.add('shift')
            if mods & (KMOD_RALT | KMOD_LALT | KMOD_MODE):
                modifiers.add('alt')
            if mods & (KMOD_RCTRL | KMOD_LCTRL):
                modifiers.add('ctrl')
            if mods & (KMOD_RGUI | KMOD_LGUI):
                modifiers.add('meta')
            if mods & KMOD_NUM:
                modifiers.add('numlock')
            if mods & KMOD_CAPS:
                modifiers.add('capslock')

        if key is not None:
            if key in (KMOD_RSHIFT, KMOD_LSHIFT):
                modifiers.add('shift')
            if key in (KMOD_RALT, KMOD_LALT, KMOD_MODE):
                modifiers.add('alt')
            if key in (KMOD_RCTRL, KMOD_LCTRL):
                modifiers.add('ctrl')
            if key in (KMOD_RGUI, KMOD_LGUI):
                modifiers.add('meta')
            if key == KMOD_NUM:
                modifiers.add('numlock')
            if key == KMOD_CAPS:
                modifiers.add('capslock')

        self._modifiers = list(modifiers)
        return

    def request_keyboard(
            self, callback, target, input_type='text', keyboard_suggestions=True
    ):
        self._nui_keyboard = super(WindowNUI, self).\
            request_keyboard(
            callback, target, input_type, keyboard_suggestions
        )
        self._win.show_keyboard()
        return self._nui_keyboard

    def release_keyboard(self, *largs):
        super(WindowNUI, self).release_keyboard(*largs)
        self._win.hide_keyboard()
        self._nui_keyboard = None
        return True

    def map_key(self, original_key, new_key):
        self.key_map[original_key] = new_key

    def unmap_key(self, key):
        if key in self.key_map:
            del self.key_map[key]
