#!/bin/sh
# Builds KivyRepresentable's GitHub Pages site: the docs (MkDocs Material)
# with the playground, whose page (docs/editor) runs WebPlayground — a
# KivyAppView running kivy_playground — built for the browser into ./app
# and copied into the site as editor/app (after MkDocs, which would turn the
# .md files among the app's resources into pages).
#
#   ./build.sh            the playground app, then the site into ./site
#   ./build.sh serve      the same, then serves ./site
#                         (http://127.0.0.1:8000/playground/)
#   ./build.sh native     WebPlayground for this machine instead:
#                         swift/.build/debug/WebPlayground
#
# Needs binaryen's wasm-opt. Kivy is the playground's wheels (../playground/wheelhouse; `../playground/
# build.sh [wasm] kivy` builds them). NUCLEANT_APPLICATION is where
# NucleantApplication is (its scripts/build_wasm_app.py); default the
# sibling checkout.
set -e
cd "$(dirname "$0")"
WHEELS=../playground/wheelhouse
NUCLEANT_APPLICATION=${NUCLEANT_APPLICATION:-../../NucleantApplication}
SITE_PACKAGES=swift/Sources/WebPlayground/site_packages

rm -rf "$SITE_PACKAGES"

if [ "$1" = "native" ]; then
    # The libCKivyNUI the Kivy wheel's modules link (their rpath points there).
    (cd .. && swift build --product CKivyNUI)
    uv pip install --python 3.13 --find-links "$WHEELS" --refresh-package kivy \
        --target "$SITE_PACKAGES" ./python
    (cd swift && swift build)
    exit
fi

uv pip install --python 3.13 --python-platform wasm32-pyodide2025 --find-links "$WHEELS" \
    --refresh-package kivy --refresh-package kivy-playground --target "$SITE_PACKAGES" ./python
# The page downloads every file in it, one request each: only what runs.
# Not Kivy's examples, tests and tools, its Cython sources, install
# metadata and scripts, uv's .lock (a hidden file, which GitHub Pages
# doesn't publish), nor pygments and docutils (Kivy's CodeInput and
# RstDocument only; together half the files).
rm -rf "$SITE_PACKAGES/share" "$SITE_PACKAGES/kivy/tests" "$SITE_PACKAGES/kivy/tools" \
    "$SITE_PACKAGES/.lock" "$SITE_PACKAGES/bin" "$SITE_PACKAGES"/*.dist-info \
    "$SITE_PACKAGES/pygments" "$SITE_PACKAGES/docutils"
find "$SITE_PACKAGES" \( -name '*.pyx' -o -name '*.pxd' -o -name '*.pxi' -o -name '*.c' -o -name '*.h' \) -delete
python3 "$NUCLEANT_APPLICATION/scripts/build_wasm_app.py" WebPlayground --package-path swift \
    --release --output app
# Optimised by binaryen, without the names section the release build keeps
# (11 MB), then gzipped: GitHub Pages serves a .wasm as it is, and
# nucleant-app.js inflates a .wasm.gz itself. 80 MB → 61 MB → 22 MB.
wasm-opt -O2 --strip-debug --strip-producers app/WebPlayground.wasm -o app/WebPlayground.wasm
gzip -9 -f app/WebPlayground.wasm

uvx --with mkdocs-material mkdocs build
cp -R app site/editor/app
# GitHub Pages lets browsers keep a page for 10 minutes, and Safari keeps the
# editor page inside the playground's frame longer: each build's editor page
# and its own files get a URL of their own. (Not the app's: nucleant-app.js
# reads the name and the .gz from the wasm's URL.)
VERSION=$(date +%s)
sed -i.orig "s|src=\"../editor/\"|src=\"../editor/?v=$VERSION\"|" site/playground/index.html
sed -i.orig -E "s/(href|src)=\"(editor\.css|layout\.js|editor\.js)\"/\1=\"\2?v=$VERSION\"/" site/editor/index.html
rm site/playground/index.html.orig site/editor/index.html.orig

if [ "$1" = "serve" ]; then
    python3 -m http.server --directory site --bind 127.0.0.1 8000
fi
