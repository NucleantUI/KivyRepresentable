#!/bin/sh
# Builds the playground app: Kivy's shared C api, the playground package with
# its dependencies (the nui Kivy wheel from ./wheelhouse) into the Swift app's
# site_packages resource, then the app. Run it: swift/.build/debug/PlaygroundApp#
#   ./build.sh            the app, with the Kivy wheel already in ./wheelhouse
#   ./build.sh kivy       rebuild the Kivy wheel (kivy2x, nui backends) first
#
# In the browser — Python is Pyodide's (the CPython package), Kivy the wheel
# cibuildwheel's pyodide platform builds; the page is served on
# http://127.0.0.1:8080:
#
#   ./build.sh wasm       the page, with the Pyodide Kivy wheel already in ./wheelhouse
#   ./build.sh wasm kivy  rebuild that wheel first
#
# http://127.0.0.1:8080/?arg=showcase runs the showcase, as
# `PlaygroundApp showcase` does.
set -e
cd "$(dirname "$0")"

if [ "$1" = "wasm" ]; then
    if [ "$2" = "kivy" ]; then
        CIBW_PLATFORM=pyodide CIBW_BUILD='cp313-*' \
        CIBW_ENVIRONMENT='USE_NUI=1 USE_SDL2=0 USE_SDL3=0 USE_GSTREAMER=0 USE_PANGOFT2=0 KIVY_CROSS_PLATFORM=emscripten' \
            uvx --from cibuildwheel==4.3.1 cibuildwheel ../kivy2x --output-dir wheelhouse
    fi
    rm -rf swift/Sources/PlaygroundApp/wasm/site_packages
    uv pip install --python 3.13 --python-platform wasm32-pyodide2025 --find-links wheelhouse \
        --refresh-package kivy --target swift/Sources/PlaygroundApp/wasm/site_packages .
    python3 ../../NucleantApplication/scripts/build_wasm_app.py PlaygroundApp --package-path swift --serve
    exit
fi

# The libCKivyNUI the Kivy wheel's modules link (their rpath points here).
(cd .. && swift build --product CKivyNUI)

if [ "$1" = "kivy" ]; then
    (cd ../kivy2x && USE_NUI=1 USE_SDL2=0 USE_GSTREAMER=0 USE_PANGOFT2=0 \
        uv build --wheel --python 3.13 --out-dir ../playground/wheelhouse)
fi

rm -rf swift/Sources/PlaygroundApp/site_packages
uv pip install --python 3.13 --find-links wheelhouse --refresh-package kivy \
    --target swift/Sources/PlaygroundApp/site_packages .

(cd swift && swift build)
