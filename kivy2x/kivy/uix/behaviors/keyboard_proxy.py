"""
kivy/uix/behaviors/keyboard_proxy.py
=====================================

Android IME bridge for Kivy TextInput.

On Android this module replaces the SDL keyboard path with a native
``KivyKeyboardProxy`` Java view (see kivy/java/KivyKeyboardProxy.java).
That view holds the real Android IME focus, so:

- Autocorrect, autocomplete and gesture / swipe typing work.
- Composing text (CJK, Indic scripts, predictive keyboards) works.
- The Done / Search / Go IME action button correctly fires on_text_validate.
- Physical keyboard arrows, backspace, etc. all generate the right events.
- None of it goes through SDL — the decade-old bugs simply do not exist.

On every other platform (desktop / iOS) the module is a transparent no-op;
FocusBehavior/TextInput continues to use the normal keyboard path.

Usage
-----
This module is imported and activated automatically by textinput.py on Android.
You do not need to import it manually unless you are building a custom widget.
"""

from kivy.utils import platform

__all__ = ('AndroidKeyboardProxy',)

# ---------------------------------------------------------------------------
# Guard: only activate on Android; everywhere else this is a no-op mixin.
# ---------------------------------------------------------------------------

if platform == 'android':
    from kivy.clock import Clock
    from kivy.logger import Logger

    try:
        from jnius import autoclass, java_method, PythonJavaClass
        _jnius_available = True
    except ImportError:
        _jnius_available = False
        Logger.warning(
            'KeyboardProxy: jnius not available; '
            'falling back to SDL keyboard handling.'
        )

    if _jnius_available:
        # -----------------------------------------------------------------
        #  Java glue
        # -----------------------------------------------------------------
        _PythonActivity = autoclass('org.kivy.android.PythonActivity')
        _KivyKeyboardProxy = autoclass('org.kivy.android.KivyKeyboardProxy')

        # A module-level singleton – there is only one soft keyboard.
        _proxy_instance = None

        def _get_proxy():
            global _proxy_instance
            if _proxy_instance is None:
                activity = _PythonActivity.mActivity
                _proxy_instance = _KivyKeyboardProxy(activity)
            return _proxy_instance

        # ------------------------------------------------------------------
        #  Python implementation of KivyKeyboardProxy.TextInputListener
        # ------------------------------------------------------------------

        class _PyListener(PythonJavaClass):
            """Routes Java IME events back to the active TextInput widget."""

            __javainterfaces__ = [
                'org/kivy/android/KivyKeyboardProxy$TextInputListener'
            ]
            __javacontext__ = 'app'

            def __init__(self, widget):
                super().__init__()
                self._widget = widget

            @java_method('(Ljava/lang/String;)V')
            def onText(self, text):
                w = self._widget
                if w is None:
                    return
                # Schedule on main thread; IMM callbacks arrive on UI thread
                Clock.schedule_once(lambda dt: w._proxy_on_text(text), 0)

            @java_method('(Ljava/lang/String;I)V')
            def onComposing(self, composing, delete_back):
                w = self._widget
                if w is None:
                    return
                Clock.schedule_once(
                    lambda dt: w._proxy_on_composing(composing, delete_back), 0)

            @java_method('(Ljava/lang/String;)V')
            def onAction(self, action):
                w = self._widget
                if w is None:
                    return
                Clock.schedule_once(
                    lambda dt: w._proxy_on_action(action), 0)

            @java_method('(II)V')
            def onDeleteSurrounding(self, before_length, after_length):
                w = self._widget
                if w is None:
                    return
                Clock.schedule_once(
                    lambda dt: w._proxy_on_delete_surrounding(before_length, after_length), 0)

            @java_method('()V')
            def onHide(self):
                w = self._widget
                if w is None:
                    return
                Clock.schedule_once(lambda dt: w._proxy_on_hide(), 0)

        # ------------------------------------------------------------------
        #  The mixin
        # ------------------------------------------------------------------

        class AndroidKeyboardProxy:
            """
            Mixin that replaces SDL keyboard handling with the native Android
            IME proxy for any FocusBehavior/TextInput-derived widget.

            Mix in *before* TextInput in the MRO::

                class MyInput(AndroidKeyboardProxy, TextInput):
                    pass
            """

            # Set to True so Kivy's TextInput skips SDL on_textinput path
            _proxy_keyboard_active = False

            # ------------------------------------------------------------------
            # Override FocusBehavior keyboard binding
            # ------------------------------------------------------------------

            def _bind_keyboard(self):
                """Replace SDL request_keyboard with our Java proxy."""
                super()._bind_keyboard()
                self._start_proxy_keyboard()
                self.bind(cursor=self._proxy_update_selection,
                          selection_text=self._proxy_update_selection,
                          text=self._proxy_update_selection)

            def _unbind_keyboard(self):
                """Stop the proxy and let FocusBehavior clean up."""
                self.unbind(cursor=self._proxy_update_selection,
                            selection_text=self._proxy_update_selection,
                            text=self._proxy_update_selection)
                self._stop_proxy_keyboard()
                super()._unbind_keyboard()

            def _proxy_update_selection(self, *largs):
                if not getattr(self, '_proxy_keyboard_active', False):
                    return
                if self._selection:
                    sel_start = min(self._selection_from, self._selection_to)
                    sel_end = max(self._selection_from, self._selection_to)
                else:
                    sel_start = self.cursor_index()
                    sel_end = sel_start
                
                notify_imm = not getattr(self, '_proxy_ime_updating', False)
                _get_proxy().updateState(sel_start, sel_end, self.text, notify_imm)

            # ------------------------------------------------------------------
            # Proxy lifecycle
            # ------------------------------------------------------------------

            def _start_proxy_keyboard(self):
                if not _jnius_available:
                    return
                proxy = _get_proxy()
                listener = _PyListener(self)
                self._proxy_listener = listener
                proxy.setListener(listener)
                input_type = getattr(self, 'input_type', 'text') or 'text'
                suggestions = getattr(self, 'keyboard_suggestions', True)
                multiline = getattr(self, 'multiline', False)

                from kivy.core.window import Window
                softinput_mode = Window.softinput_mode or ''
                
                wx, wy = Window.system_size
                x, y = self.to_window(self.x, self.y)
                w, h = self.width, self.height

                android_y = wy - (y + h)

                proxy.show(
                    input_type,
                    suggestions,
                    multiline,
                    softinput_mode,
                    int(x),
                    int(android_y),
                    int(w),
                    int(h)
                )
                self._proxy_keyboard_active = True
                Logger.debug(
                    'KeyboardProxy: started for %r (input_type=%s)',
                    self, input_type
                )

            def _stop_proxy_keyboard(self):
                if not _jnius_available:
                    return
                if self._proxy_keyboard_active:
                    _get_proxy().hide()
                    self._proxy_keyboard_active = False
                    self._proxy_listener = None
                    Logger.debug('KeyboardProxy: stopped for %r', self)

            # ------------------------------------------------------------------
            # Callbacks from _PyListener (always called on the Kivy main thread)
            # ------------------------------------------------------------------

            def _proxy_on_text(self, text):
                """Plain committed text from the IME."""
                self._proxy_ime_updating = True
                if self._selection:
                    self.delete_selection()
                self.insert_text(text, False)
                self._proxy_ime_updating = False

            def _proxy_on_composing(self, composing, delete_back):
                """
                Composing text update: first delete delete_back chars
                then insert composing (which may be empty to just delete).
                """
                self._proxy_ime_updating = True
                # Delete the old composing region
                if delete_back > 0:
                    ci = self.cursor_index()
                    self._selection_from = max(0, ci - delete_back)
                    self._selection_to = ci
                    self._selection = True
                    self.delete_selection()
                elif self._selection:
                    self.delete_selection()

                # Insert the new composing text (if any)
                if composing:
                    self.insert_text(composing, False)
                self._proxy_ime_updating = False

            def _proxy_on_action(self, action):
                """Special-key action from the IME or physical keyboard."""
                # Map Java action strings -> Kivy interesting_keys logic
                _action_map = {
                    'backspace': 'backspace',
                    'del':       'del',
                    'enter':     'enter',
                    'escape':    'escape',
                    'left':      'cursor_left',
                    'right':     'cursor_right',
                    'up':        'cursor_up',
                    'down':      'cursor_down',
                    'home':      'cursor_home',
                    'end':       'cursor_end',
                    'pageup':    'cursor_pgup',
                    'pagedown':  'cursor_pgdn',
                }
                kivy_action = _action_map.get(action)
                if kivy_action is None:
                    return

                # Re-use the existing _key_down machinery so undo/redo,
                # selection and multiline all behave identically.
                key_tuple = (None, None, kivy_action, 1)
                self._key_down(key_tuple)

            def _proxy_on_delete_surrounding(self, before_length, after_length):
                """Batch deletion from the IME (e.g. long-press delete / one-tap clear)."""
                self._proxy_ime_updating = True
                
                if self._selection:
                    sel_start = min(self._selection_from, self._selection_to)
                    sel_end = max(self._selection_from, self._selection_to)
                else:
                    sel_start = sel_end = self.cursor_index()

                keep_start = max(0, sel_start - before_length)
                keep_end = min(len(self.text), sel_end + after_length)

                # Delete the right portion first so indices for the left portion don't shift
                if after_length > 0 and keep_end > sel_end:
                    self._selection_from = sel_end
                    self._selection_to = keep_end
                    self._selection = True
                    self.delete_selection()
                    
                # Now delete the left portion
                if before_length > 0 and sel_start > keep_start:
                    self._selection_from = keep_start
                    self._selection_to = sel_start
                    self._selection = True
                    self.delete_selection()

                self._proxy_ime_updating = False

            def _proxy_on_hide(self):
                """IME dismissed (back button or Done)."""
                if self.focus:
                    self.focus = False

    else:
        # jnius not available – plain no-op mixin
        class AndroidKeyboardProxy:
            pass

else:
    # Non-Android platform – plain no-op mixin
    class AndroidKeyboardProxy:
        """No-op on non-Android platforms."""
        pass
