'''
The C side of the `nui` window: Kivy's end of the shared C api
(kivy_nui.h) that a KivyRepresentable host registers with before Python
starts.

`poll()` hands back the same tuples `_window_sdl2.pyx` `poll()` does, so
window_nui.py handles events the way window_sdl2.py does. Instead of a loop
of its own, the window registers a tick that the host calls once per
display-sync frame.
'''

include "../../lib/kivy_nui.pxi"

from kivy.graphics.ngl_backend.ngl_nui cimport NGLNUI
import traceback

# The Python callable the host's ticks reach (WindowNUI._tick), or None.
cdef object _tick_callback = None


cdef void _on_tick(void *context, double dt) noexcept with gil:
    if _tick_callback is None:
        return
    try:
        _tick_callback(dt)
    except BaseException:
        # Nothing above us can take a Python exception: the caller is the
        # host's display sync.
        traceback.print_exc()


_cursors = {
    'arrow': KIVY_NUI_CURSOR_ARROW,
    'ibeam': KIVY_NUI_CURSOR_IBEAM,
    'wait': KIVY_NUI_CURSOR_WAIT,
    'crosshair': KIVY_NUI_CURSOR_CROSSHAIR,
    'wait_arrow': KIVY_NUI_CURSOR_WAIT_ARROW,
    'size_nwse': KIVY_NUI_CURSOR_SIZE_NWSE,
    'size_nesw': KIVY_NUI_CURSOR_SIZE_NESW,
    'size_we': KIVY_NUI_CURSOR_SIZE_WE,
    'size_ns': KIVY_NUI_CURSOR_SIZE_NS,
    'size_all': KIVY_NUI_CURSOR_SIZE_ALL,
    'no': KIVY_NUI_CURSOR_NO,
    'hand': KIVY_NUI_CURSOR_HAND,
}


def is_hosted():
    return kivy_nui_is_hosted()


cdef class _WindowNUIStorage:

    # The GL context (ngl_backend), as `_WindowSDLStorage` keeps its
    # EGLANGLE. None with the `mock` backend, which draws nowhere.
    cdef NGLNUI ngl

    def create_gl_context(self, gl_backend_name):
        if gl_backend_name == 'mock' or self.ngl is not None:
            return
        ngl = NGLNUI()
        ngl.create_context()
        self.ngl = ngl

    def destroy_gl_context(self):
        if self.ngl is not None:
            self.ngl.destroy_context()
            self.ngl = None

    def set_tick(self, callback):
        '''Start (callback) or stop (None) receiving the host's ticks.'''
        global _tick_callback
        cdef KivyNUIKivy kivy
        _tick_callback = callback
        if callback is None:
            kivy_nui_set_kivy(NULL)
        else:
            kivy.context = NULL
            kivy.tick = _on_tick
            kivy_nui_set_kivy(&kivy)

    def window_metrics(self):
        '''(width, height, pixel_width, pixel_height, density, dpi).'''
        cdef KivyNUIWindowMetrics m
        kivy_nui_get_window_metrics(&m)
        return (m.width, m.height, m.pixel_width, m.pixel_height,
                m.density, m.dpi)

    @property
    def window_size(self):
        cdef KivyNUIWindowMetrics m
        kivy_nui_get_window_metrics(&m)
        return m.width, m.height

    def _get_gl_size(self):
        cdef KivyNUIWindowMetrics m
        kivy_nui_get_window_metrics(&m)
        return m.pixel_width, m.pixel_height

    def flip(self):
        if self.ngl is not None:
            self.ngl.swap_buffers()
        else:
            kivy_nui_present()

    def set_window_title(self, title):
        kivy_nui_set_title(title.encode('utf-8'))

    def set_system_cursor(self, str name):
        if name not in _cursors:
            return False
        kivy_nui_set_system_cursor(_cursors[name])
        return True

    def _set_cursor_state(self, value):
        kivy_nui_set_cursor_visible(bool(value))

    def show_keyboard(self):
        kivy_nui_show_keyboard()

    def hide_keyboard(self):
        kivy_nui_hide_keyboard()

    def request_close(self):
        kivy_nui_request_close()

    def poll(self):
        '''The next queued event as `_window_sdl2.pyx` `poll()` shapes it,
        False when the queue is empty, None for one to skip.'''
        cdef KivyNUIEvent event
        if not kivy_nui_poll_event(&event):
            return False

        t = event.type
        if t == KIVY_NUI_EVENT_QUIT:
            return ('quit', )
        elif t == KIVY_NUI_EVENT_MOUSE_MOTION:
            return ('mousemotion', event.mouse.x, event.mouse.y)
        elif t == KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN:
            return ('mousebuttondown', event.mouse.x, event.mouse.y,
                    event.mouse.button)
        elif t == KIVY_NUI_EVENT_MOUSE_BUTTON_UP:
            return ('mousebuttonup', event.mouse.x, event.mouse.y,
                    event.mouse.button)
        elif t == KIVY_NUI_EVENT_MOUSE_WHEEL:
            x = event.wheel.x
            y = event.wheel.y
            if x != 0:
                suffix = 'left' if x > 0 else 'right'
            elif y != 0:
                suffix = 'down' if y > 0 else 'up'
            else:
                return None
            # SDL's tuple plus the cursor position SDL's window asked
            # SDL_GetMouseState for.
            return ('mousewheel' + suffix, x, y, None,
                    event.wheel.mouse_x, event.wheel.mouse_y)
        elif t == KIVY_NUI_EVENT_FINGER_MOTION:
            return ('fingermotion', event.finger.finger_id, event.finger.x,
                    event.finger.y, event.finger.pressure)
        elif t == KIVY_NUI_EVENT_FINGER_DOWN:
            return ('fingerdown', event.finger.finger_id, event.finger.x,
                    event.finger.y, event.finger.pressure)
        elif t == KIVY_NUI_EVENT_FINGER_UP:
            return ('fingerup', event.finger.finger_id, event.finger.x,
                    event.finger.y, event.finger.pressure)
        elif t == KIVY_NUI_EVENT_KEY_DOWN:
            return ('keydown', event.key.mod, event.key.keycode,
                    event.key.scancode, None)
        elif t == KIVY_NUI_EVENT_KEY_UP:
            return ('keyup', event.key.mod, event.key.keycode,
                    event.key.scancode, None)
        elif t == KIVY_NUI_EVENT_TEXT_INPUT:
            return ('textinput', event.text.utf8.decode('utf-8'))
        elif t == KIVY_NUI_EVENT_TEXT_EDIT:
            return ('textedit', event.text.utf8.decode('utf-8'))
        elif t == KIVY_NUI_EVENT_WINDOW_EXPOSED:
            return ('windowexposed', )
        elif t == KIVY_NUI_EVENT_WINDOW_RESIZED:
            return ('windowresized', event.window.data1, event.window.data2)
        elif t == KIVY_NUI_EVENT_WINDOW_MINIMIZED:
            return ('windowminimized', )
        elif t == KIVY_NUI_EVENT_WINDOW_MAXIMIZED:
            return ('windowmaximized', )
        elif t == KIVY_NUI_EVENT_WINDOW_RESTORED:
            return ('windowrestored', )
        elif t == KIVY_NUI_EVENT_WINDOW_SHOWN:
            return ('windowshown', )
        elif t == KIVY_NUI_EVENT_WINDOW_HIDDEN:
            return ('windowhidden', )
        elif t == KIVY_NUI_EVENT_WINDOW_ENTER:
            return ('windowenter', )
        elif t == KIVY_NUI_EVENT_WINDOW_LEAVE:
            return ('windowleave', )
        elif t == KIVY_NUI_EVENT_WINDOW_FOCUS_GAINED:
            return ('windowfocusgained', )
        elif t == KIVY_NUI_EVENT_WINDOW_FOCUS_LOST:
            return ('windowfocuslost', )
        elif t == KIVY_NUI_EVENT_WINDOW_CLOSE:
            return ('windowclose', )
        elif t == KIVY_NUI_EVENT_WINDOW_MOVED:
            return ('windowmoved', event.window.data1, event.window.data2)
        elif t == KIVY_NUI_EVENT_WINDOW_DISPLAY_CHANGED:
            return ('windowdisplaychanged', event.window.data1,
                    event.window.data2)
        elif t == KIVY_NUI_EVENT_DROP_BEGIN:
            return ('dropbegin', event.drop.x, event.drop.y)
        elif t == KIVY_NUI_EVENT_DROP_FILE:
            # SDL hands the path over as bytes.
            return ('dropfile', <bytes>event.drop.utf8)
        elif t == KIVY_NUI_EVENT_DROP_TEXT:
            return ('droptext', <bytes>event.drop.utf8)
        elif t == KIVY_NUI_EVENT_DROP_END:
            return ('dropend', )
        elif t == KIVY_NUI_EVENT_APP_TERMINATING:
            return ('app_terminating', )
        elif t == KIVY_NUI_EVENT_APP_LOW_MEMORY:
            return ('app_lowmemory', )
        elif t == KIVY_NUI_EVENT_APP_WILL_ENTER_BACKGROUND:
            return ('app_willenterbackground', )
        elif t == KIVY_NUI_EVENT_APP_DID_ENTER_BACKGROUND:
            return ('app_didenterbackground', )
        elif t == KIVY_NUI_EVENT_APP_WILL_ENTER_FOREGROUND:
            return ('app_willenterforeground', )
        elif t == KIVY_NUI_EVENT_APP_DID_ENTER_FOREGROUND:
            return ('app_didenterforeground', )
        return None
