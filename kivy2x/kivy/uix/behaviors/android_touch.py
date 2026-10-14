'''
Android Touch Behavior
======================

A Kivy-specific helper that wraps the universal `android.touch.TouchListener`.
It uses Kivy's `Window` and coordinate system to hit-test widgets and intercept
touches at the SDL surface level before they enter Kivy's standard dispatch.
'''

from kivy.core.window import Window


class KivyTouchListener:
    """Convenience API to register a global Android intercept touch listener
    specifically for Kivy widgets.

    This class provides the Kivy-specific hit-testing logic for the universal
    `android.touch.TouchListener`.
    """

    __target_widget = None

    @classmethod
    def register_listener(cls, target_widget):
        """Register the global intercept touch listener if not already set.

        Parameters:
            target_widget: The widget used as the reference during hit-testing.
                If the touch lands on this widget and no other widget is found
                under the touch, the event will be consumed by the intercept
                listener.
        """
        try:
            from android.touch import TouchListener
        except ImportError:
            return  # Not on Android or android module not available

        if TouchListener.is_listener_set():
            return
            
        cls.__target_widget = target_widget
        TouchListener.register_listener(cls._on_touch_listener)

    @classmethod
    def unregister_listener(cls):
        """Unregister the global intercept touch listener, if any."""
        try:
            from android.touch import TouchListener
            TouchListener.unregister_listener()
        except ImportError:
            pass
        cls.__target_widget = None

    @classmethod
    def is_listener_set(cls):
        """Report whether the intercept listener reference is set."""
        try:
            from android.touch import TouchListener
            return TouchListener.is_listener_set()
        except ImportError:
            return False

    @classmethod
    def _on_touch_listener(cls, event):
        """Callback used by the installed intercept listener.

        If the event has action DOWN (0), it performs a hit-test against
        Kivy's Window children. Otherwise, it returns False.
        """
        if event.getAction() == 0:  # MotionEvent.ACTION_DOWN
            return cls._hit_test(event)
        return False

    @classmethod
    def _hit_test(cls, event):
        """Perform a front-to-back hit-test against Kivy Window children."""
        x = event.getX(0)
        y = event.getY(0)

        # invert Y !
        y = Window.height - y
        # x, y are in Window coordinate. Try to select the widget under the
        # touch.
        me = None
        for child in reversed(Window.children):
            widget = cls._pick(child, x, y)
            if not widget:
                continue
            if cls.__target_widget is widget:
                me = widget
                # keep scanning to ensure no other widget is hit
                continue
            # any non-target hit means we should not intercept
            return False
        return cls.__target_widget is me

    @classmethod
    def _pick(cls, widget, x, y):
        """Pick the deepest child widget at coordinates."""
        # Fast exit if the root doesn't collide
        if not widget.collide_point(x, y):
            return None

        # Always descend through the first colliding child in z-order
        current = widget
        lx, ly = x, y
        while True:
            # Transform coordinates once per level
            nlx, nly = current.to_local(lx, ly)
            hit_child = None
            for child in reversed(current.children):
                if child.collide_point(nlx, nly):
                    # keep the last colliding child in this order
                    hit_child = child
            if hit_child is None:
                # No deeper child collides; current is the deepest hit
                return current
            
            lx, ly = nlx, nly
            current = hit_child
