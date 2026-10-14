'''
Runnable
========
'''

from jnius import PythonJavaClass, java_method
from android import mActivity

# Cache of functions table. In older Android versions the number of JNI references
# is limited, so by caching them we avoid running out.
__functionstable__ = {}


class Runnable(PythonJavaClass):
    '''Wrapper around Java Runnable class. This class can be used to schedule a
    call of a Python function into the PythonActivity thread.
    '''

    __javainterfaces__ = ['java/lang/Runnable']
    __runnables__ = []

    def __init__(self, func):
        super().__init__()
        self.func = func
        self.calls = []

    def __call__(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        Runnable.__runnables__.append(self)
        mActivity.runOnUiThread(self)

    @java_method('()V')
    def run(self):
        try:
            if self.calls:
                args, kwargs = self.calls.pop(0)
                self.func(*args, **kwargs)
        except:  # noqa E722
            import traceback
            traceback.print_exc()

        if self in Runnable.__runnables__:
            Runnable.__runnables__.remove(self)


def run_on_ui_thread(f):
    '''Decorator to create automatically a :class:`Runnable` object with the
    function. The function will be delayed and call into the Activity thread.
    '''
    if f not in __functionstable__:
        rfunction = Runnable(f)  # store the runnable function
        __functionstable__[f] = {"rfunction": rfunction}
    rfunction = __functionstable__[f]["rfunction"]

    def f2(*args, **kwargs):
        rfunction(*args, **kwargs)

    return f2
