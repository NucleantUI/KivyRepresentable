from setuptools import setup, Extension
from Cython.Build import cythonize
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

BOOTSTRAP      = os.environ.get("BOOTSTRAP", "sdl2")
ANDROID_API    = os.environ.get("ANDROID_API", "24")
KIVY_VERSION   = os.environ.get("KIVY_VERSION", "2.3.1")
KIVY_INDEX     = "https://pypi.anaconda.org/kivyschool/simple"

cmake_toolchain = os.environ.get("CMAKE_TOOLCHAIN_FILE", "")

# ---------------------------------------------------------------------------
# Library dirs
# ---------------------------------------------------------------------------
if cmake_toolchain:
    cross_lib_dir = Path(cmake_toolchain).parent / "python" / "prefix" / "lib"
    library_dirs = [str(cross_lib_dir)]
else:
    # Fallback: p4a recipe path
    env_dirs = os.environ.get("ANDROID_LIBS_DIR", "")
    library_dirs = [d for d in env_dirs.split(":") if d]
    cross_lib_dir = None

lib_dict = {
    "sdl2": ["SDL2", "SDL2_image", "SDL2_mixer", "SDL2_ttf"],
    "sdl3": ["SDL3", "SDL3_image", "SDL3_mixer", "SDL3_ttf"],
}
sdl_libs = lib_dict.get(BOOTSTRAP, ["main"])

# ---------------------------------------------------------------------------
# Config generation  (config.pxi / config.h / config.py)
# Only runs during a real cibuildwheel Android build where CMAKE_TOOLCHAIN_FILE
# is set.  The committed default files handle the earlier dep-scan phase.
# ---------------------------------------------------------------------------
def _generate_config():
    if BOOTSTRAP not in ("sdl2", "sdl3"):
        raise ValueError(f"Unsupported BOOTSTRAP={BOOTSTRAP!r}")

    activity_class = os.environ.get("ACTIVITY_CLASS_NAME", "org.kivy.android.PythonActivity")
    service_class  = os.environ.get("SERVICE_CLASS_NAME",  "org.kivy.android.PythonService")

    config = {
        "BOOTSTRAP":                BOOTSTRAP,
        "IS_SDL2":                  int(BOOTSTRAP == "sdl2"),
        "IS_SDL3":                  int(BOOTSTRAP == "sdl3"),
        "PY2":                      0,
        "ANDROID_LIBS_DIR":         str(cross_lib_dir),
        "JAVA_NAMESPACE":           "org.kivy.android",
        "JNI_NAMESPACE":            "org/kivy/android",
        "ACTIVITY_CLASS_NAME":      activity_class,
        "ACTIVITY_CLASS_NAMESPACE": activity_class.replace(".", "/"),
        "SERVICE_CLASS_NAME":       service_class,
    }

    android_dir = Path(__file__).parent / "src" / "android"
    with (
        open(android_dir / "config.pxi", "w") as fpxi,
        open(android_dir / "config.h",   "w") as fh,
        open(android_dir / "config.py",  "w") as fpy,
    ):
        for key, value in config.items():
            fpxi.write(f"DEF {key} = {value!r}\n")
            fpy.write(f"{key} = {value!r}\n")
            if isinstance(value, int):
                fh.write(f"#define {key} {value}\n")
            else:
                fh.write(f'#define {key} "{value}"\n')

        if BOOTSTRAP == "sdl2":
            fh.write("JNIEnv *SDL_AndroidGetJNIEnv(void);\n")
            fh.write("#define SDL_ANDROID_GetJNIEnv SDL_AndroidGetJNIEnv\n")
        else:
            fh.write("JNIEnv *SDL_GetAndroidJNIEnv(void);\n")
            fh.write("#define SDL_ANDROID_GetJNIEnv SDL_GetAndroidJNIEnv\n")

# ---------------------------------------------------------------------------
# SDL lib harvesting — copies libSDL2/3.so into the cross-Python prefix/lib
# so the NDK linker finds -lSDL2 / -lSDL3.  Same approach as pyjnius.sh.
# ---------------------------------------------------------------------------
def _harvest_sdl_libs():
    prefix = {"sdl2": "libSDL2", "sdl3": "libSDL3"}.get(BOOTSTRAP)
    if not prefix:
        return

    m = re.search(r"android_(arm64_v8a|x86_64|armeabi_v7a)", cmake_toolchain)
    if not m:
        raise RuntimeError(f"Cannot detect arch from CMAKE_TOOLCHAIN_FILE={cmake_toolchain!r}")
    arch     = m.group(1)
    plat_tag = f"android_{ANDROID_API}_{arch}"
    py_ver   = f"{sys.version_info.major}{sys.version_info.minor}"

    cross_lib_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.check_call([
            sys.executable, "-m", "pip", "download",
            f"kivy=={KIVY_VERSION}",
            "--index-url", KIVY_INDEX,
            "--platform", plat_tag,
            "--python-version", py_ver,
            "--only-binary=:all:",
            "--no-deps",
            "-d", tmp,
        ])
        whl = next(Path(tmp).glob("*.whl"))
        with zipfile.ZipFile(whl) as z:
            # Copy every libSDL2*.so / libSDL3*.so found in the wheel
            matches = [n for n in z.namelist()
                       if Path(n).name.startswith(prefix) and Path(n).name.endswith(".so")]
            if not matches:
                raise RuntimeError(f"No {prefix}*.so found in kivy wheel for {arch}")
            for member in matches:
                z.extract(member, tmp)
                dest = cross_lib_dir / Path(member).name
                shutil.copy(Path(tmp) / member, dest)
                print(f"Copied {Path(member).name} -> {cross_lib_dir}")

# ---------------------------------------------------------------------------
# Run only during the real build (CMAKE_TOOLCHAIN_FILE is set by cibuildwheel
# after the initial dep-scan phase, so this is safe to guard on).
# ---------------------------------------------------------------------------
if cmake_toolchain:
    _generate_config()
    _harvest_sdl_libs()

# ---------------------------------------------------------------------------
# Extensions
# ---------------------------------------------------------------------------
src = "src"
include_dirs = [f"{src}/android"]

modules = [
    Extension(
        "android._android",
        [f"{src}/android/_android.pyx", f"{src}/android/_android_jni.c"],
        libraries=sdl_libs + ["log"],
        library_dirs=library_dirs,
        include_dirs=include_dirs,
    ),
    Extension(
        "android._android_billing",
        [f"{src}/android/_android_billing.pyx", f"{src}/android/_android_billing_jni.c"],
        libraries=[sdl_libs[0], "log"],   # needs libSDL2/3 for SDL_AndroidGetJNIEnv
        library_dirs=library_dirs,
        include_dirs=include_dirs,
    ),
    Extension(
        "android._android_sound",
        [f"{src}/android/_android_sound.pyx", f"{src}/android/_android_sound_jni.c"],
        libraries=[sdl_libs[0], "log"],   # needs libSDL2/3 for SDL_ANDROID_GetJNIEnv
        library_dirs=library_dirs,
        include_dirs=include_dirs,
        extra_compile_args=["-include", "stdlib.h"],
    ),
]

setup(
    ext_modules=cythonize(
        modules,
        compiler_directives={"language_level": "3"},
        include_path=include_dirs,
    ),
)
