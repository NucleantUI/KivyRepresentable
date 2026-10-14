#!/bin/bash
set -e -x

# ANGLE (pre-built)
ANGLE__VERSION="chromium-7151_rev1"
ANGLE__IOS__URL="https://github.com/kivy/angle-builder/releases/download/${ANGLE__VERSION}/angle-iphoneall-universal.tar.gz"

# iOS SDL2
IOS__SDL2__VERSION="2.28.5"
IOS__SDL2__URL="https://github.com/libsdl-org/SDL/releases/download/release-${IOS__SDL2__VERSION}/SDL2-${IOS__SDL2__VERSION}.tar.gz"
IOS__SDL2__FOLDER="SDL2-${IOS__SDL2__VERSION}"

# iOS SDL2_image
IOS__SDL2_IMAGE__VERSION="2.8.0"
IOS__SDL2_IMAGE__URL="https://github.com/libsdl-org/SDL_image/releases/download/release-${IOS__SDL2_IMAGE__VERSION}/SDL2_image-${IOS__SDL2_IMAGE__VERSION}.tar.gz"
IOS__SDL2_IMAGE__FOLDER="SDL2_image-${IOS__SDL2_IMAGE__VERSION}"

# iOS SDL2_mixer
IOS__SDL2_MIXER__VERSION="2.8.0"
IOS__SDL2_MIXER__URL="https://github.com/libsdl-org/SDL_mixer/releases/download/release-${IOS__SDL2_MIXER__VERSION}/SDL2_mixer-${IOS__SDL2_MIXER__VERSION}.tar.gz"
IOS__SDL2_MIXER__FOLDER="SDL2_mixer-${IOS__SDL2_MIXER__VERSION}"

# iOS SDL2_ttf
IOS__SDL2_TTF__VERSION="2.22.0"
IOS__SDL2_TTF__URL="https://github.com/libsdl-org/SDL_ttf/releases/download/release-${IOS__SDL2_TTF__VERSION}/SDL2_ttf-${IOS__SDL2_TTF__VERSION}.tar.gz"
IOS__SDL2_TTF__FOLDER="SDL2_ttf-${IOS__SDL2_TTF__VERSION}"

# Skip rebuild if all xcframeworks are already present (set FORCE_REBUILD=1 to override)
_DIST_FW="ios-kivy-dependencies/dist/Frameworks"
if [ -z "${FORCE_REBUILD:-}" ] && \
   [ -d "$_DIST_FW/SDL2.xcframework" ] && \
   [ -d "$_DIST_FW/SDL2_image.xcframework" ] && \
   [ -d "$_DIST_FW/SDL2_mixer.xcframework" ] && \
   [ -d "$_DIST_FW/SDL2_ttf.xcframework" ] && \
   [ -d "$_DIST_FW/libEGL.xcframework" ] && \
   [ -d "$_DIST_FW/libGLESv2.xcframework" ]; then
    echo "iOS dependencies already present, skipping rebuild. Set FORCE_REBUILD=1 to force."
    exit 0
fi

# Clean the dependencies folder
rm -rf ios-kivy-dependencies

# Create the dependencies folder
mkdir ios-kivy-dependencies

# Download the dependencies
echo "Downloading dependencies..."
mkdir ios-kivy-dependencies/download
pushd ios-kivy-dependencies/download
curl -L $IOS__SDL2__URL -o "${IOS__SDL2__FOLDER}.tar.gz"
curl -L $IOS__SDL2_IMAGE__URL -o "${IOS__SDL2_IMAGE__FOLDER}.tar.gz"
curl -L $IOS__SDL2_MIXER__URL -o "${IOS__SDL2_MIXER__FOLDER}.tar.gz"
curl -L $IOS__SDL2_TTF__URL -o "${IOS__SDL2_TTF__FOLDER}.tar.gz"
curl -L $ANGLE__IOS__URL -o "angle-iphoneall-universal.tar.gz"
popd

# Extract the dependencies into build folder
echo "Extracting dependencies..."
mkdir ios-kivy-dependencies/build
pushd ios-kivy-dependencies/build
tar -xzf ../download/${IOS__SDL2__FOLDER}.tar.gz
tar -xzf ../download/${IOS__SDL2_IMAGE__FOLDER}.tar.gz
tar -xzf ../download/${IOS__SDL2_MIXER__FOLDER}.tar.gz
tar -xzf ../download/${IOS__SDL2_TTF__FOLDER}.tar.gz
popd

# Create distribution folder
echo "Creating distribution folder..."
mkdir ios-kivy-dependencies/dist
mkdir ios-kivy-dependencies/dist/Frameworks
mkdir ios-kivy-dependencies/dist/include
mkdir ios-kivy-dependencies/dist/lib

# Build the dependencies
pushd ios-kivy-dependencies/build

echo "-- Build SDL2 (Universal)"
pushd $IOS__SDL2__FOLDER
for platform in "iOS" "iOS Simulator"; do
    platform_arg=$([ "$platform" = "iOS" ] && echo "iphoneos" || echo "iphonesimulator")
    xcodebuild archive -scheme "Framework-iOS" -project Xcode/SDL/SDL.xcodeproj \
        -archivePath "Xcode/SDL/build/Release-${platform_arg}" \
        -destination "generic/platform=${platform}" -configuration Release \
        -jobs 4 \
        "BUILD_LIBRARY_FOR_DISTRIBUTION=YES" "SKIP_INSTALL=NO" \
        "MACH_O_TYPE=mh_dylib"
done
xcodebuild -create-xcframework \
    -framework Xcode/SDL/build/Release-iphoneos.xcarchive/Products/Library/Frameworks/SDL2.framework \
    -framework Xcode/SDL/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/SDL2.framework \
    -output ../../dist/Frameworks/SDL2.xcframework

# Copy SDL2 headers to distribution folder
mkdir -p ../../dist/include/SDL2
cp -a Xcode/SDL/build/Release-iphoneos.xcarchive/Products/Library/Frameworks/SDL2.framework/Headers/* \
    ../../dist/include/SDL2

popd

echo "-- Build SDL2_image (Universal)"
pushd $IOS__SDL2_IMAGE__FOLDER
SDL2_FW_SEARCH_IPHONEOS="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphoneos.xcarchive/Products/Library/Frameworks"
SDL2_FW_SEARCH_SIMULATOR="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks"
for platform in "iOS" "iOS Simulator"; do
    platform_arg=$([ "$platform" = "iOS" ] && echo "iphoneos" || echo "iphonesimulator")
    sdl2_fw_search=$([ "$platform" = "iOS" ] && echo "$SDL2_FW_SEARCH_IPHONEOS" || echo "$SDL2_FW_SEARCH_SIMULATOR")
    xcodebuild archive -scheme "Framework" -project Xcode/SDL_image.xcodeproj \
        -archivePath "Xcode/SDL_image/build/Release-${platform_arg}" \
        -destination "generic/platform=${platform}" -configuration Release \
        -jobs 4 \
        "BUILD_LIBRARY_FOR_DISTRIBUTION=YES" "SKIP_INSTALL=NO" \
        "MACH_O_TYPE=mh_dylib" \
        "FRAMEWORK_SEARCH_PATHS=${sdl2_fw_search}" \
        "HEADER_SEARCH_PATHS=${sdl2_fw_search}/SDL2.framework/Headers"
done
xcodebuild -create-xcframework \
    -framework Xcode/SDL_image/build/Release-iphoneos.xcarchive/Products/Library/Frameworks/SDL2_image.framework \
    -framework Xcode/SDL_image/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/SDL2_image.framework \
    -output ../../dist/Frameworks/SDL2_image.xcframework
popd

echo "-- Build SDL2_mixer (Universal)"
pushd $IOS__SDL2_MIXER__FOLDER
SDL2_FW_SEARCH_IPHONEOS="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphoneos.xcarchive/Products/Library/Frameworks"
SDL2_FW_SEARCH_SIMULATOR="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks"
for platform in "iOS" "iOS Simulator"; do
    platform_arg=$([ "$platform" = "iOS" ] && echo "iphoneos" || echo "iphonesimulator")
    sdl2_fw_search=$([ "$platform" = "iOS" ] && echo "$SDL2_FW_SEARCH_IPHONEOS" || echo "$SDL2_FW_SEARCH_SIMULATOR")
    xcodebuild archive -scheme "Framework" -project Xcode/SDL_mixer.xcodeproj \
        -archivePath "Xcode/SDL_mixer/build/Release-${platform_arg}" \
        -destination "generic/platform=${platform}" -configuration Release \
        -jobs 4 \
        "BUILD_LIBRARY_FOR_DISTRIBUTION=YES" "SKIP_INSTALL=NO" \
        "MACH_O_TYPE=mh_dylib" \
        "FRAMEWORK_SEARCH_PATHS=${sdl2_fw_search}" \
        "HEADER_SEARCH_PATHS=${sdl2_fw_search}/SDL2.framework/Headers"
done
xcodebuild -create-xcframework \
    -framework Xcode/SDL_mixer/build/Release-iphoneos.xcarchive/Products/Library/Frameworks/SDL2_mixer.framework \
    -framework Xcode/SDL_mixer/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/SDL2_mixer.framework \
    -output ../../dist/Frameworks/SDL2_mixer.xcframework
popd

echo "-- Build SDL2_ttf (Universal)"
pushd $IOS__SDL2_TTF__FOLDER
# Download external dependencies (FreeType) if needed
# Remove pre-existing stub dirs from the tarball to allow git clone to succeed
if [ -f external/download.sh ]; then
    rm -rf external/freetype external/harfbuzz
    sh ./external/download.sh
fi
SDL2_FW_SEARCH_IPHONEOS="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphoneos.xcarchive/Products/Library/Frameworks"
SDL2_FW_SEARCH_SIMULATOR="$(pwd)/../${IOS__SDL2__FOLDER}/Xcode/SDL/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks"
for platform in "iOS" "iOS Simulator"; do
    platform_arg=$([ "$platform" = "iOS" ] && echo "iphoneos" || echo "iphonesimulator")
    sdl2_fw_search=$([ "$platform" = "iOS" ] && echo "$SDL2_FW_SEARCH_IPHONEOS" || echo "$SDL2_FW_SEARCH_SIMULATOR")
    xcodebuild archive -scheme "Framework" -project Xcode/SDL_ttf.xcodeproj \
        -archivePath "Xcode/SDL_ttf/build/Release-${platform_arg}" \
        -destination "generic/platform=${platform}" -configuration Release \
        -jobs 4 \
        "BUILD_LIBRARY_FOR_DISTRIBUTION=YES" "SKIP_INSTALL=NO" \
        "MACH_O_TYPE=mh_dylib" \
        "FRAMEWORK_SEARCH_PATHS=${sdl2_fw_search}" \
        "HEADER_SEARCH_PATHS=${sdl2_fw_search}/SDL2.framework/Headers"
done
xcodebuild -create-xcframework \
    -framework Xcode/SDL_ttf/build/Release-iphoneos.xcarchive/Products/Library/Frameworks/SDL2_ttf.framework \
    -framework Xcode/SDL_ttf/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/SDL2_ttf.framework \
    -output ../../dist/Frameworks/SDL2_ttf.xcframework
popd

popd

# Download, extract and install ANGLE pre-built xcframeworks
echo "-- Installing ANGLE for iOS (pre-built)"
mkdir -p ios-kivy-dependencies/download/angle-ios
pushd ios-kivy-dependencies/download/angle-ios
tar -xzf ../angle-iphoneall-universal.tar.gz
# Copy xcframeworks to dist/Frameworks/
find . -name "libEGL.xcframework" -exec cp -r {} ../../dist/Frameworks/ \;
find . -name "libGLESv2.xcframework" -exec cp -r {} ../../dist/Frameworks/ \;
# Copy headers to dist/include/
find . -name "*.h" -path "*/EGL/*" | head -1 | xargs -I{} dirname {} | xargs -I{} cp -r {} ../../dist/include/ 2>/dev/null || true
find . -name "*.h" -path "*/GLES2/*" | head -1 | xargs -I{} dirname {} | xargs -I{} cp -r {} ../../dist/include/ 2>/dev/null || true
find . -name "khrplatform.h" | head -1 | xargs -I{} dirname {} | xargs -I{} cp -r {} ../../dist/include/ 2>/dev/null || true
popd
echo "ANGLE installed to ios-kivy-dependencies/dist/"

echo ""
echo "iOS SDL2 dependencies built successfully!"
echo "Set KIVY_DEPS_ROOT=$(pwd)/ios-kivy-dependencies to use them."
