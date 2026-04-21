#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HermesDesktop"
APP_DISPLAY_NAME="Hermes Desktop"
BUNDLE_PATH="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_PATH="$BUNDLE_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
SWIFTPM_HOME="$ROOT_DIR/.swiftpm-home"
SCRATCH_PATH="$ROOT_DIR/.build"
ICON_SOURCE="$ROOT_DIR/packaging/AppIcon-1024.png"
ICONSET_PATH="$ROOT_DIR/packaging/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/packaging/HermesDesktop.icns"
PLIST_PATH="$ROOT_DIR/packaging/Info.plist"
SHADER_SOURCE_PATH="$ROOT_DIR/Vendor/SwiftTerm/Sources/SwiftTerm/Apple/Metal/Shaders.metal"
UNIVERSAL_EXECUTABLE_PATH="$SCRATCH_PATH/${APP_NAME}-universal"

if [[ -n "${HERMES_MAC_ARCHS:-}" ]]; then
    read -r -a BUILD_ARCHES <<<"$HERMES_MAC_ARCHS"
else
    BUILD_ARCHES=(arm64 x86_64)
fi

mkdir -p \
    "$ROOT_DIR/dist" \
    "$SWIFTPM_HOME/cache" \
    "$SWIFTPM_HOME/configuration" \
    "$SWIFTPM_HOME/security" \
    "$SWIFTPM_HOME/module-cache"

pick_sdk() {
    if [[ -n "${SDKROOT:-}" && -d "${SDKROOT}" ]]; then
        printf '%s\n' "$SDKROOT"
        return
    fi

    local developer_dir
    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    if [[ -n "$developer_dir" && "$developer_dir" != "/Library/Developer/CommandLineTools" ]]; then
        xcrun --show-sdk-path
        return
    fi

    local clt_sdks="/Library/Developer/CommandLineTools/SDKs"
    local selected=""

    if [[ -d "$clt_sdks" ]]; then
        selected="$(ls -d "$clt_sdks"/MacOSX15.[0-9]*.sdk 2>/dev/null | sort | tail -n 1 || true)"
        if [[ -z "$selected" ]]; then
            selected="$(ls -d "$clt_sdks"/MacOSX15*.sdk 2>/dev/null | grep -v 'MacOSX15.sdk$' | sort | tail -n 1 || true)"
        fi
        if [[ -z "$selected" ]]; then
            selected="$(ls -d "$clt_sdks"/MacOSX*.sdk 2>/dev/null | grep -v 'MacOSX26' | sort | tail -n 1 || true)"
        fi
    fi

    if [[ -z "$selected" ]]; then
        selected="$(xcrun --show-sdk-path)"
    fi

    printf '%s\n' "$selected"
}

derive_version() {
    if [[ -n "${HERMES_VERSION:-}" ]]; then
        printf '%s\n' "$HERMES_VERSION"
        return
    fi

    local tag
    tag="$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true)"
    if [[ -n "$tag" ]]; then
        printf '%s\n' "${tag#v}"
    fi
}

derive_build_number() {
    if [[ -n "${HERMES_BUILD:-}" ]]; then
        printf '%s\n' "$HERMES_BUILD"
        return
    fi

    git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || true
}

stamp_plist_versions() {
    local plist="$1"
    local version build

    version="$(derive_version)"
    build="$(derive_build_number)"

    if [[ -n "$version" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
    fi

    if [[ -n "$build" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
    fi

    STAMPED_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")"
    STAMPED_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")"
}

generate_icon() {
    mkdir -p "$ICONSET_PATH"

    if [[ ! -f "$ICON_SOURCE" ]]; then
        env "${BUILD_ENV[@]}" swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$ICON_SOURCE"
    fi

    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
    cp "$ICON_SOURCE" "$ICONSET_PATH/icon_512x512@2x.png"

    env "${BUILD_ENV[@]}" swift "$ROOT_DIR/scripts/build-icns.swift" "$ICONSET_PATH" "$ICNS_PATH"
    iconutil -c iconset "$ICNS_PATH" -o /tmp/hermes-desktop-icon-validation.iconset >/dev/null
    rm -rf /tmp/hermes-desktop-icon-validation.iconset
}

BUILD_SDK="$(pick_sdk)"
BUILD_ENV=(
    "CLANG_MODULE_CACHE_PATH=$SWIFTPM_HOME/module-cache"
    "SDKROOT=$BUILD_SDK"
)
SWIFT_FLAGS=(
    build
    -c release
    --disable-sandbox
    --manifest-cache local
    --cache-path "$SWIFTPM_HOME/cache"
    --config-path "$SWIFTPM_HOME/configuration"
    --security-path "$SWIFTPM_HOME/security"
    --scratch-path "$SCRATCH_PATH"
)

build_arch() {
    local arch="$1"
    echo "Building $APP_DISPLAY_NAME for $arch with SDK: $BUILD_SDK"
    env "${BUILD_ENV[@]}" swift "${SWIFT_FLAGS[@]}" --arch "$arch"
}

bin_dir_for_arch() {
    local arch="$1"
    env "${BUILD_ENV[@]}" swift "${SWIFT_FLAGS[@]}" --arch "$arch" --show-bin-path
}

echo "Building $APP_DISPLAY_NAME universal bundle for architectures: ${BUILD_ARCHES[*]}"
for arch in "${BUILD_ARCHES[@]}"; do
    build_arch "$arch"
done

EXECUTABLE_PATHS=()
for arch in "${BUILD_ARCHES[@]}"; do
    BIN_DIR="$(bin_dir_for_arch "$arch")"
    EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

    if [[ ! -x "$EXECUTABLE_PATH" ]]; then
        echo "error: expected executable not found for $arch at $EXECUTABLE_PATH" >&2
        exit 1
    fi

    EXECUTABLE_PATHS+=("$EXECUTABLE_PATH")
done

if [[ ! -f "$SHADER_SOURCE_PATH" ]]; then
    echo "error: expected SwiftTerm shader source not found at $SHADER_SOURCE_PATH" >&2
    exit 1
fi

generate_icon

rm -rf "$BUNDLE_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH"

rm -f "$UNIVERSAL_EXECUTABLE_PATH"
if (( ${#EXECUTABLE_PATHS[@]} == 1 )); then
    cp "${EXECUTABLE_PATHS[0]}" "$UNIVERSAL_EXECUTABLE_PATH"
else
    lipo -create -output "$UNIVERSAL_EXECUTABLE_PATH" "${EXECUTABLE_PATHS[@]}"
fi

cp "$UNIVERSAL_EXECUTABLE_PATH" "$MACOS_PATH/$APP_NAME"
cp "$PLIST_PATH" "$CONTENTS_PATH/Info.plist"
stamp_plist_versions "$CONTENTS_PATH/Info.plist"
cp "$ICNS_PATH" "$RESOURCES_PATH/AppIcon.icns"
cp "$SHADER_SOURCE_PATH" "$RESOURCES_PATH/Shaders.metal"

# Copy localization bundles from the first available arch build output
LPROJ_SOURCE_ARCH="${BUILD_ARCHES[0]}"
LPROJ_BUNDLE="$SCRATCH_PATH/${LPROJ_SOURCE_ARCH}-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$LPROJ_BUNDLE" ]]; then
    for lproj_dir in "$LPROJ_BUNDLE"/*.lproj; do
        [[ -d "$lproj_dir" ]] && cp -r "$lproj_dir" "$RESOURCES_PATH/"
    done
fi

codesign --force --deep --sign - "$BUNDLE_PATH" >/dev/null
codesign --verify --deep --strict "$BUNDLE_PATH" >/dev/null

echo
echo "App bundle created:"
echo "  $BUNDLE_PATH"
echo "Version: ${STAMPED_VERSION} (build ${STAMPED_BUILD})"
echo "Architectures: $(lipo -archs "$MACOS_PATH/$APP_NAME")"
echo "Ad-hoc signed bundle created: macOS may still require right-click > Open on first launch."
