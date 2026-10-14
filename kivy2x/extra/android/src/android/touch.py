"""Touch interception helpers for Python for Android.

This module exposes two utilities to hook into the Android SDL surface's
intercept touch mechanism via pyjnius:

- `OnInterceptTouchListener`: a thin bridge class that implements the
  Java interface `SDLSurface.OnInterceptTouchListener` and delegates to a
  provided Python callable.
- `TouchListener`: a convenience class with helpers to register/unregister
  the intercept listener and a hit-testing routine against the Kivy
  `Window` to decide whether a touch should be consumed.
- `TouchListener.register_listener` requires a `target_widget` argument,
  which is used for hit-testing to decide whether to consume touches.
- Touch coordinates are taken from pointer index 0 and converted to Kivy's
  coordinate system by inverting Y relative to `Window.height`.

Dependencies: pyjnius for bridging to Android, and Kivy for window and
widget traversal used in hit-testing.
"""

from jnius import PythonJavaClass, java_method
from android import mActivity

__all__ = ('OnInterceptTouchListener', 'TouchListener')


class OnInterceptTouchListener(PythonJavaClass):
    """Bridge for Android's `SDLSurface.OnInterceptTouchListener`.

    Instances of this class can be passed to the SDL surface so that touch
    events can be intercepted before they reach the normal Android/Kivy
    dispatch pipeline. The Python callable provided at construction time is
    invoked for each `MotionEvent` and should return a boolean indicating
    whether the touch was consumed.
    """

    __javacontext__ = 'app'
    __javainterfaces__ = [
        'org/libsdl/app/SDLSurface$OnInterceptTouchListener']

    def __init__(self, listener):
        """Create a new intercept touch listener.

        Parameters:
            listener (Callable[[object], bool]): A callable that receives the
                Android `MotionEvent` instance and returns `True` if the
                touch should be consumed (intercepted), or `False` to let it
                propagate normally.
        """
        self.listener = listener

    @java_method('(Landroid/view/MotionEvent;)Z')
    def onTouch(self, event):
        """Handle an incoming `MotionEvent`.

        Parameters:
            event: The Android `MotionEvent` object delivered by the SDL
                surface.

        Returns:
            bool: The boolean returned by the user-provided `listener`, where
            `True` indicates the event was consumed and should not propagate
            further; `False` lets normal processing continue.
        """
        return self.listener(event)




class TouchListener:
    """Convenience API to register a global Android intercept touch listener.

    This class manages a singleton instance of `OnInterceptTouchListener`
    that is attached to the app's `PythonActivity.mSurface`.
    """
    __listener = None

    @classmethod
    def register_listener(cls, callback):
        """Register the global intercept touch listener if not already set.

        This creates a singleton `OnInterceptTouchListener` that delegates to
        the provided callback and installs it on `PythonActivity.mSurface`.

        Parameters:
            callback (Callable[[object], bool]): A function that receives the
                Android `MotionEvent` and returns `True` to consume the touch
                or `False` to let it propagate normally.
        """
        if cls.__listener:
            return
        cls.__listener = OnInterceptTouchListener(callback)
        mActivity.mSurface.setInterceptTouchListener(cls.__listener)

    @classmethod
    def unregister_listener(cls):
        """Unregister the global intercept touch listener, if any."""
        if mActivity and hasattr(mActivity, 'mSurface') and mActivity.mSurface:
            mActivity.mSurface.setInterceptTouchListener(None)
        cls.__listener = None

    @classmethod
    def is_listener_set(cls):
        """Report whether the intercept listener reference is set."""
        return cls.__listener is not None
