#!/bin/bash
set -e -x

# Android SDL2
ANDROID__SDL2__VERSION="2.30.11"
ANDROID__SDL2__URL="https://github.com/libsdl-org/SDL/releases/download/release-${ANDROID__SDL2__VERSION}/SDL2-${ANDROID__SDL2__VERSION}.tar.gz"
ANDROID__SDL2__FOLDER="SDL2-${ANDROID__SDL2__VERSION}"

# Android SDL2_image
ANDROID__SDL2_IMAGE__VERSION="2.8.2"
ANDROID__SDL2_IMAGE__URL="https://github.com/libsdl-org/SDL_image/releases/download/release-${ANDROID__SDL2_IMAGE__VERSION}/SDL2_image-${ANDROID__SDL2_IMAGE__VERSION}.tar.gz"
ANDROID__SDL2_IMAGE__FOLDER="SDL2_image-${ANDROID__SDL2_IMAGE__VERSION}"

# Android SDL2_mixer
ANDROID__SDL2_MIXER__VERSION="2.8.0"
ANDROID__SDL2_MIXER__URL="https://github.com/libsdl-org/SDL_mixer/releases/download/release-${ANDROID__SDL2_MIXER__VERSION}/SDL2_mixer-${ANDROID__SDL2_MIXER__VERSION}.tar.gz"
ANDROID__SDL2_MIXER__FOLDER="SDL2_mixer-${ANDROID__SDL2_MIXER__VERSION}"

# Android SDL2_ttf
ANDROID__SDL2_TTF__VERSION="2.22.0"
ANDROID__SDL2_TTF__URL="https://github.com/libsdl-org/SDL_ttf/releases/download/release-${ANDROID__SDL2_TTF__VERSION}/SDL2_ttf-${ANDROID__SDL2_TTF__VERSION}.tar.gz"
ANDROID__SDL2_TTF__FOLDER="SDL2_ttf-${ANDROID__SDL2_TTF__VERSION}"

ANDROID_MIN_API=21
ANDROID_ABIS="arm64-v8a x86_64"

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "ERROR: ANDROID_NDK_HOME is not set. Please set it to the Android NDK root."
    exit 1
fi

TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "ERROR: Android CMake toolchain not found at $TOOLCHAIN_FILE"
    exit 1
fi

BUILD_DIR="$(pwd)/android-kivy-dependencies"

# Clean the dependencies folder
rm -rf "$BUILD_DIR"

# Create the dependencies folder
mkdir -p "$BUILD_DIR/download"
mkdir -p "$BUILD_DIR/build"
mkdir -p "$BUILD_DIR/dist/include"
mkdir -p "$BUILD_DIR/dist/lib"

# Download the dependencies
echo "Downloading dependencies..."
pushd "$BUILD_DIR/download"
curl -L $ANDROID__SDL2__URL -o "${ANDROID__SDL2__FOLDER}.tar.gz"
curl -L $ANDROID__SDL2_IMAGE__URL -o "${ANDROID__SDL2_IMAGE__FOLDER}.tar.gz"
curl -L $ANDROID__SDL2_MIXER__URL -o "${ANDROID__SDL2_MIXER__FOLDER}.tar.gz"
curl -L $ANDROID__SDL2_TTF__URL -o "${ANDROID__SDL2_TTF__FOLDER}.tar.gz"
popd

# Extract the dependencies into build folder
echo "Extracting dependencies..."
pushd "$BUILD_DIR/build"
tar -xzf ../download/${ANDROID__SDL2__FOLDER}.tar.gz
tar -xzf ../download/${ANDROID__SDL2_IMAGE__FOLDER}.tar.gz
tar -xzf ../download/${ANDROID__SDL2_MIXER__FOLDER}.tar.gz
tar -xzf ../download/${ANDROID__SDL2_TTF__FOLDER}.tar.gz
popd

# Download vendored external dependencies (git submodules not included in tarballs)
echo "Downloading SDL2_mixer external dependencies (ogg, vorbis, mp3)..."
pushd "$BUILD_DIR/build/$ANDROID__SDL2_MIXER__FOLDER/external"
bash download.sh
popd

# SDL2_ttf tarball already bundles external/freetype — no download needed.

# Build for each ABI
for ABI in $ANDROID_ABIS; do
    echo ""
    echo "=== Building for ABI: $ABI ==="
    mkdir -p "$BUILD_DIR/dist/libs/$ABI"

    STAGING="$BUILD_DIR/staging-$ABI"
    mkdir -p "$STAGING"

    # Build SDL2
    echo "-- Build SDL2 ($ABI)"
    pushd "$BUILD_DIR/build/$ANDROID__SDL2__FOLDER"
    cmake -S . -B "build-$ABI" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_MIN_API" \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DSDL_SHARED=ON \
        -DSDL_STATIC=OFF \
        -DCMAKE_INSTALL_PREFIX="$STAGING"
    cmake --build "build-$ABI" --config Release --parallel
    cmake --install "build-$ABI" --config Release
    popd

    SDL2_DIR="$STAGING/lib/cmake/SDL2"

    # Build SDL2_image
    echo "-- Build SDL2_image ($ABI)"
    pushd "$BUILD_DIR/build/$ANDROID__SDL2_IMAGE__FOLDER"
    cmake -S . -B "build-$ABI" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_MIN_API" \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DSDL2IMAGE_VENDORED=ON \
        -DSDL2IMAGE_PNG=ON \
        -DSDL2IMAGE_JPG=ON \
        -DSDL2_DIR="$SDL2_DIR" \
        -DCMAKE_INSTALL_PREFIX="$STAGING"
    cmake --build "build-$ABI" --config Release --parallel
    cmake --install "build-$ABI" --config Release
    popd

    # Build SDL2_mixer
    echo "-- Build SDL2_mixer ($ABI)"
    pushd "$BUILD_DIR/build/$ANDROID__SDL2_MIXER__FOLDER"
    cmake -S . -B "build-$ABI" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_MIN_API" \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DSDL2MIXER_VENDORED=ON \
        -DSDL2MIXER_MP3=ON \
        -DSDL2MIXER_OGG=ON \
        -DSDL2_DIR="$SDL2_DIR" \
        -DCMAKE_INSTALL_PREFIX="$STAGING"
    cmake --build "build-$ABI" --config Release --parallel
    cmake --install "build-$ABI" --config Release
    popd

    # Build SDL2_ttf
    echo "-- Build SDL2_ttf ($ABI)"
    pushd "$BUILD_DIR/build/$ANDROID__SDL2_TTF__FOLDER"
    cmake -S . -B "build-$ABI" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_MIN_API" \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DSDL2TTF_VENDORED=ON \
        -DSDL2TTF_HARFBUZZ=OFF \
        -DSDL2TTF_SAMPLES=OFF \
        -DSDL2_DIR="$SDL2_DIR" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_INSTALL_PREFIX="$STAGING"
    cmake --build "build-$ABI" --config Release --parallel
    cmake --install "build-$ABI" --config Release
    popd

    # Copy .so files to dist/libs/{ABI}/
    echo "-- Collecting .so files for $ABI"
    cp "$STAGING/lib/"libSDL2*.so "$BUILD_DIR/dist/libs/$ABI/"
done

# Copy headers from one staging dir — same for all ABIs
echo "-- Collecting headers"
# SDL2 and sub-library headers are all installed under include/SDL2/
if [ -d "$BUILD_DIR/staging-arm64-v8a/include/SDL2" ]; then
    cp -r "$BUILD_DIR/staging-arm64-v8a/include/SDL2" "$BUILD_DIR/dist/include/"
fi

# Collect SDL2 Java sources (SDLActivity etc.) — the Android app/activity glue.
# These ship in SDL2's source tarball under android-project/app/src/main/java/
# and are required by any app embedding SDL2 on Android. We expose the whole
# `org/libsdl/app/` tree so downstream tooling (ksproject) can pick them up
# the same way it picks up .so files.
echo "-- Collecting SDL2 Java sources"
SDL2_JAVA_SRC="$BUILD_DIR/build/$ANDROID__SDL2__FOLDER/android-project/app/src/main/java"
if [ -d "$SDL2_JAVA_SRC" ]; then
    mkdir -p "$BUILD_DIR/dist/java"
    cp -r "$SDL2_JAVA_SRC/." "$BUILD_DIR/dist/java/"
else
    echo "WARNING: SDL2 Java sources not found at $SDL2_JAVA_SRC"
fi

echo ""
echo "Android SDL2 dependencies built successfully!"
echo "Output: $BUILD_DIR"
echo ""
echo "Layout:"
echo "  dist/libs/arm64-v8a/  — .so files for arm64"
echo "  dist/libs/x86_64/     — .so files for x86_64"
echo "  dist/include/SDL2/    — headers for all SDL2 libraries"
echo "  dist/java/org/libsdl/app/ — SDL2 Java glue (SDLActivity, etc.)"
echo ""
echo "Set KIVY_DEPS_ROOT=$BUILD_DIR to use them in setup.py."
