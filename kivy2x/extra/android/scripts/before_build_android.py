"""
cibuildwheel before-build script for the android package (Android platform).

Runs inside the cibuildwheel build environment before pip calls setup.py.

What it does
------------
1. Detects the target arch from CMAKE_TOOLCHAIN_FILE.
2. Downloads the kivy Android wheel from anaconda.org/kivyschool to harvest
   libSDL2.so (or libSDL3.so), exactly like kivy_scripts/pyjnius.sh does.
3. Copies the SDL shared library into the cross-Python prefix/lib so the NDK
   linker finds it via the -L path that cibuildwheel already provides.
4. Generates src/android/config.pxi, config.h and config.py with the constants
   that _android.pyx / _android_jni.c require (BOOTSTRAP, IS_SDL2, etc.).
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile
import tempfile
from pathlib import Path

KIVY_INDEX = "https://pypi.anaconda.org/kivyschool/simple"
KIVY_VERSION = os.environ.get("KIVY_VERSION", "2.3.1")
BOOTSTRAP = os.environ.get("BOOTSTRAP", "sdl2")
ANDROID_API = os.environ.get("ANDROID_API", "24")

SDL_LIB_NAME = {
    "sdl2": "libSDL2.so",
    "sdl3": "libSDL3.so",
}

PLAT_TAG_MAP = {
    "arm64_v8a":   f"android_{ANDROID_API}_arm64_v8a",
    "x86_64":      f"android_{ANDROID_API}_x86_64",
    "armeabi_v7a": f"android_{ANDROID_API}_armeabi_v7a",
}


def detect_arch():
    toolchain = os.environ.get("CMAKE_TOOLCHAIN_FILE", "")
    m = re.search(r"android_(arm64_v8a|x86_64|armeabi_v7a)", toolchain)
    if m:
        return m.group(1)
    raise RuntimeError(
        f"Cannot detect arch from CMAKE_TOOLCHAIN_FILE={toolchain!r}"
    )


def get_cross_lib_dir():
    toolchain = os.environ["CMAKE_TOOLCHAIN_FILE"]
    return Path(toolchain).parent / "python" / "prefix" / "lib"


def harvest_sdl_lib(arch, cross_lib_dir):
    lib_name = SDL_LIB_NAME.get(BOOTSTRAP)
    if not lib_name:
        return

    plat_tag = PLAT_TAG_MAP[arch]
    py_ver = f"{sys.version_info.major}{sys.version_info.minor}"

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
            matches = [n for n in z.namelist() if Path(n).name == lib_name]
            if not matches:
                raise RuntimeError(
                    f"{lib_name} not found in kivy wheel for {arch}"
                )
            z.extract(matches[0], tmp)
            shutil.copy(Path(tmp) / matches[0], cross_lib_dir / lib_name)

    print(f"Copied {lib_name} -> {cross_lib_dir}")


def generate_config(cross_lib_dir):
    if BOOTSTRAP not in ("sdl2", "sdl3"):
        raise ValueError(f"Unsupported BOOTSTRAP={BOOTSTRAP!r}")

    java_ns = "org.kivy.android"
    jni_ns = "org/kivy/android"

    activity_class = os.environ.get(
        "ACTIVITY_CLASS_NAME", "org.kivy.android.PythonActivity"
    )
    service_class = os.environ.get(
        "SERVICE_CLASS_NAME", "org.kivy.android.PythonService"
    )

    config = {
        "BOOTSTRAP":                BOOTSTRAP,
        "IS_SDL2":                  int(BOOTSTRAP == "sdl2"),
        "IS_SDL3":                  int(BOOTSTRAP == "sdl3"),
        "PY2":                      0,
        "ANDROID_LIBS_DIR":         str(cross_lib_dir),
        "JAVA_NAMESPACE":           java_ns,
        "JNI_NAMESPACE":            jni_ns,
        "ACTIVITY_CLASS_NAME":      activity_class,
        "ACTIVITY_CLASS_NAMESPACE": activity_class.replace(".", "/"),
        "SERVICE_CLASS_NAME":       service_class,
    }

    # Anchor to this file's location so the path is correct regardless of cwd.
    # scripts/ -> project root -> src/android/
    android_dir = Path(__file__).parent.parent / "src" / "android"
    android_dir.mkdir(parents=True, exist_ok=True)

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
        elif BOOTSTRAP == "sdl3":
            fh.write("JNIEnv *SDL_GetAndroidJNIEnv(void);\n")
            fh.write("#define SDL_ANDROID_GetJNIEnv SDL_GetAndroidJNIEnv\n")

    print(f"Generated config.pxi / config.h / config.py for BOOTSTRAP={BOOTSTRAP}")


arch = detect_arch()
cross_lib_dir = get_cross_lib_dir()
cross_lib_dir.mkdir(parents=True, exist_ok=True)

harvest_sdl_lib(arch, cross_lib_dir)
generate_config(cross_lib_dir)
