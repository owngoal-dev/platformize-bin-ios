#!/usr/bin/env bash
#
# Stage, ad-hoc sign, and build one .deb from a payload directory that
# build-ios.sh assembled. Called once per bootstrap layout; the payload is the
# same both times, only the install prefix and the architecture label differ.

set -Eeuo pipefail

if [[ "$#" -ne 5 ]]; then
    echo "usage: $0 <payload-dir> <output-deb> <version> <architecture> <install-prefix>" >&2
    echo "note: install-prefix is empty for roothide and /var/jb for rootless" >&2
    exit 64
fi

payload="$1"
output_deb="$2"
version="$3"
architecture="$4"
install_prefix="$5"

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=../Configuration/upstream.env
source "$repository_root/Configuration/upstream.env"

: "${PROGRAM:?}"
: "${MIN_IOS:?}"
: "${UPSTREAM_REF:?}"

package_id="${PACKAGE_ID:-wiki.qaq.fastfetch}"
control_template="$repository_root/Packaging/DEBIAN/control"
entitlements="$repository_root/Packaging/${PROGRAM}.entitlements"

for input in "$control_template" "$entitlements"; do
    [[ -f "$input" ]] || { echo "error: missing packaging input: $input" >&2; exit 66; }
done

[[ -d "$payload" ]] || { echo "error: no payload directory at $payload" >&2; exit 66; }
[[ -f "$payload/usr/bin/$PROGRAM" ]] || { echo "error: payload has no usr/bin/$PROGRAM" >&2; exit 66; }

[[ "$output_deb" == *.deb ]] || { echo "error: output must end in .deb" >&2; exit 64; }
[[ "$package_id" =~ ^[a-z0-9][a-z0-9+.-]+$ ]] || { echo "error: invalid package id" >&2; exit 64; }
[[ "$version" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || { echo "error: invalid version" >&2; exit 64; }
[[ "$architecture" =~ ^[A-Za-z0-9][A-Za-z0-9-]+$ ]] || { echo "error: invalid architecture" >&2; exit 64; }
[[ "$install_prefix" =~ ^(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] || { echo "error: invalid install prefix" >&2; exit 64; }

for tool in ldid dpkg-deb; do
    command -v "$tool" >/dev/null || { echo "error: $tool is not installed" >&2; exit 69; }
done

vtool -show-build "$payload/usr/bin/$PROGRAM" 2>/dev/null | grep -qE '^ *platform (IOS|2)$' || {
    echo "error: $payload/usr/bin/$PROGRAM is not an iOS binary" >&2
    exit 65
}

output_name="$(basename "$output_deb")"
mkdir -p "$(dirname "$output_deb")"
output_directory="$(cd -- "$(dirname -- "$output_deb")" && pwd -P)"
output_deb="$output_directory/$output_name"

staging="$(mktemp -d "${TMPDIR:-/tmp}/${PROGRAM}-deb.XXXXXX")"
temporary_deb="$output_directory/.$output_name.tmp.$$"
signed_entitlements="$(mktemp "${TMPDIR:-/tmp}/${PROGRAM}-entitlements.XXXXXX")"
trap 'rm -rf -- "$staging"; rm -f -- "$temporary_deb" "$signed_entitlements"' EXIT
chmod 0755 "$staging"

debian="$staging/DEBIAN"
installed_root="$staging$install_prefix"
installed_binary="$installed_root/usr/bin/$PROGRAM"
mkdir -p "$debian" "$installed_root"

# The payload is already laid out as usr/...; the whole tree moves under the
# bootstrap prefix. Nothing in it names a path, so no substitution is needed:
# the binary finds its own presets and etc relative to where it was installed.
/usr/bin/ditto "$payload" "$installed_root"
find "$installed_root" -type d -exec chmod 0755 {} +
find "$installed_root" -type f -exec chmod 0644 {} +
chmod 0755 "$installed_binary"

ldid -S"$entitlements" -Cadhoc "$installed_binary"

require_true() {
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$1" "$signed_entitlements" 2>/dev/null || true)" == true ]] || {
        echo "error: signed binary is missing entitlement: $1" >&2
        exit 65
    }
}
ldid -e "$installed_binary" >"$signed_entitlements"
require_true platform-application
require_true com.apple.private.security.no-sandbox
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.private.security.container-required' \
    "$signed_entitlements" 2>/dev/null || true)" == false ]] || {
    echo "error: $installed_binary needs com.apple.private.security.container-required = false" >&2
    exit 65
}

installed_size="$(du -sk "$installed_root" | awk '{print $1}')"
upstream_label="${UPSTREAM_REPO##*/}@${UPSTREAM_REF:0:12}"
sed \
    -e "s|@PACKAGE_ID@|$package_id|g" \
    -e "s|@VERSION@|$version|g" \
    -e "s|@ARCHITECTURE@|$architecture|g" \
    -e "s|@INSTALLED_SIZE@|$installed_size|g" \
    -e "s|@MIN_IOS@|$MIN_IOS|g" \
    -e "s|@UPSTREAM@|$upstream_label|g" \
    "$control_template" >"$debian/control"
chmod 0644 "$debian/control"
if grep -q '@[A-Z_]*@' "$debian/control"; then
    echo "error: control still holds unsubstituted placeholders:" >&2
    grep -n '@[A-Z_]*@' "$debian/control" | sed 's/^/       /' >&2
    exit 65
fi

# Nothing personal or secret leaves this machine inside a package.
"$repository_root/Scripts/check-sensitive.sh" "$staging"

dpkg-deb --root-owner-group -Zzstd -b "$staging" "$temporary_deb" >/dev/null

[[ "$(dpkg-deb -f "$temporary_deb" Package)" == "$package_id" ]]
[[ "$(dpkg-deb -f "$temporary_deb" Version)" == "$version" ]]
[[ "$(dpkg-deb -f "$temporary_deb" Architecture)" == "$architecture" ]]
contents="$(dpkg-deb --contents "$temporary_deb")"
for path in \
    "$install_prefix/usr/bin/$PROGRAM" \
    "$install_prefix/usr/share/$PROGRAM/presets/" \
    "$install_prefix/usr/share/man/man1/$PROGRAM.1"; do
    grep -qF ".$path" <<<"$contents" || {
        echo "error: package is missing $path" >&2
        exit 65
    }
done

mv -f "$temporary_deb" "$output_deb"
echo "packaged $package_id $version ($architecture, prefix '${install_prefix:-/}'): $output_deb"
shasum -a 256 "$output_deb"
