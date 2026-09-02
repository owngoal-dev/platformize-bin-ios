#!/usr/bin/env bash
#
# Cross-compile fastfetch for iOS out of a prepared source tree, verify the
# result is really an iOS binary, and assemble a payload directory.
#
# Prints the payload directory on stdout (the last line). Its contents are the
# install tree relative to the bootstrap root: usr/bin/fastfetch,
# usr/share/fastfetch/presets, completions and the man page.

set -Eeuo pipefail

if [[ "$#" -ne 2 ]]; then
    echo "usage: $0 <src-dir> <scratch-dir>" >&2
    exit 64
fi

src_dir="$1"
scratch_dir="$2"
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${PROGRAM:?}"
: "${MIN_IOS:?}"
: "${ARCH:?}"

[[ -f "$src_dir/CMakeLists.txt" ]] || {
    echo "error: $src_dir is not a prepared source tree (run Scripts/prepare-source.sh)" >&2
    exit 66
}

for tool in cmake ninja; do
    command -v "$tool" >/dev/null || { echo "error: $tool is not installed" >&2; exit 69; }
done

ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
[[ -d "$ios_sdk" && -d "$macos_sdk" ]] || { echo "error: need both the iPhoneOS and macOS SDKs; install Xcode" >&2; exit 69; }

echo "building $PROGRAM for iOS $MIN_IOS ($ARCH)" >&2
echo "  SDK: $ios_sdk" >&2

mkdir -p "$scratch_dir"

# The iPhoneOS SDK omits headers for APIs that iOS nevertheless exports:
# libproc, the routing/interface sysctls, and most of IOKit (power sources,
# storage, HID, graphics). Borrow exactly those headers from the macOS SDK;
# anything the iOS SDK does provide keeps winning because the shim only holds
# what is missing. This is what theos/Procursus do with their patched SDKs.
shim="$scratch_dir/sdk-shim"
rm -rf "$shim"
mkdir -p "$shim/sys" "$shim/net" "$shim/IOKit"
for header in libproc.h sys/proc_info.h sys/kern_control.h sys/user.h net/route.h net/if_mib.h net/if_media.h; do
    [[ -e "$ios_sdk/usr/include/$header" ]] && continue
    [[ -e "$macos_sdk/usr/include/$header" ]] || { echo "error: macOS SDK has no $header" >&2; exit 69; }
    ln -s "$macos_sdk/usr/include/$header" "$shim/$header"
done
for entry in "$macos_sdk"/System/Library/Frameworks/IOKit.framework/Headers/*; do
    name="$(basename "$entry")"
    [[ -e "$ios_sdk/System/Library/Frameworks/IOKit.framework/Headers/$name" ]] && continue
    ln -s "$entry" "$shim/IOKit/$name"
done

# Keep pkg-config from feeding Homebrew's macOS .pc files into an iOS build.
# Everything optional is dlopen'd at runtime anyway.
empty_pkgconfig="$scratch_dir/empty-pkgconfig"
mkdir -p "$empty_pkgconfig"
export PKG_CONFIG_LIBDIR="$empty_pkgconfig"
unset PKG_CONFIG_PATH

build_dir="$scratch_dir/build"
cmake -S "$src_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_MACOSX_BUNDLE=OFF \
    -DCMAKE_C_FLAGS="-isystem $shim" \
    -DCMAKE_OBJC_FLAGS="-isystem $shim" \
    -DBUILD_FLASHFETCH=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_WORDEXP=OFF \
    -DHAVE_PIPE2=0 \
    -DINSTALL_LICENSE=OFF \
    >&2
# ENABLE_WORDEXP: wordexp(3) is marked unavailable on iOS.
# HAVE_PIPE2: the iOS 27 SDK declares pipe2 but no device before 27 has it; the
#             check_function_exists probe cannot tell, so pin the answer.

cmake --build "$build_dir" >&2

executable="$build_dir/$PROGRAM"
[[ -f "$executable" ]] || { echo "error: build produced no $executable" >&2; exit 65; }

build_version="$(vtool -show-build "$executable" 2>/dev/null)"
grep -qE '^ *platform (IOS|2)$' <<<"$build_version" || {
    echo "error: $executable is not an iOS binary:" >&2
    sed 's/^/       /' <<<"$build_version" >&2
    exit 65
}

architectures="$(lipo -archs "$executable")"
[[ "$architectures" == "$ARCH" ]] || {
    echo "error: expected a $ARCH binary, got '$architectures'" >&2
    exit 65
}

while read -r dependency; do
    case "$dependency" in
    @*) ;;
    /usr/lib/* | /System/Library/Frameworks/*) ;;
    *)
        echo "error: $executable depends on a path iOS does not provide: $dependency" >&2
        exit 65
        ;;
    esac
done < <(otool -L "$executable" | tail -n +2 | awk '{print $1}')

# A symbol newer than MIN_IOS is weak-linked and NULL on older devices. Every
# such use must be null-checked in the source; list them so a new one is seen.
weak_imports="$(nm -m "$executable" | grep 'weak external' || true)"

payload="$scratch_dir/payload"
rm -rf -- "$payload"
mkdir -p "$payload"
DESTDIR="$payload" cmake --install "$build_dir" --prefix /usr >&2

[[ -f "$payload/usr/bin/$PROGRAM" ]] || { echo "error: install produced no usr/bin/$PROGRAM" >&2; exit 65; }
[[ -d "$payload/usr/share/$PROGRAM/presets" ]] || { echo "error: install produced no presets" >&2; exit 65; }

# Strip the payload copy, not the build tree, so the cached artifact remains
# useful for symbolication. package-deb.sh signs after stripping.
xcrun --sdk iphoneos strip -xS "$payload/usr/bin/$PROGRAM"
vtool -show-build "$payload/usr/bin/$PROGRAM" 2>/dev/null | grep -qE '^ *platform (IOS|2)$' || {
    echo "error: stripped $PROGRAM is no longer an iOS binary" >&2
    exit 65
}

{
    echo "built $PROGRAM: $ARCH, iOS $MIN_IOS minimum, $(du -h "$payload/usr/bin/$PROGRAM" | cut -f1 | tr -d ' ')"
    echo "payload ($(du -sh "$payload" | cut -f1 | tr -d ' ') total):"
    (cd "$payload" && find . -type f | sort | sed 's|^\./|  |')
    echo "system dependencies:"
    otool -L "$payload/usr/bin/$PROGRAM" | tail -n +2 | awk '{print "  " $1}'
    echo "weak imports (newer than iOS $MIN_IOS; must be null-checked in source):"
    if [[ -n "$weak_imports" ]]; then
        sed 's/^ */  /' <<<"$weak_imports"
    else
        echo "  (none)"
    fi
} >&2

printf '%s\n' "$payload"
