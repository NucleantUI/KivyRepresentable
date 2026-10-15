#!/bin/sh
# Builds the playground app: Kivy's shared C api, the playground package with
# its dependencies (the nui Kivy wheel from ./wheelhouse) into the Swift app's
# site_packages resource, then the app. Run it: swift/.build/debug/PlaygroundApp
#
#   ./build.sh        the app, with the Kivy wheel already in ./wheelhouse
#   ./build.sh kivy   rebuild the Kivy wheel (kivy2x, nui backends) first
set -e
cd "$(dirname "$0")"

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
