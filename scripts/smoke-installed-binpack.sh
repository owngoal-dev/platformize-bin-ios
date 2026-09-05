#!/bin/sh
# Run ON the device after installing the packages normally. This only invokes
# version/self-test commands; it does not install, update, or authenticate.
failures=0
architecture=$(dpkg --print-architecture) || exit 1
case "$architecture" in
    iphoneos-arm64|iphoneos-arm64e) ;;
    *) echo "unsupported bootstrap architecture: $architecture" >&2; exit 1 ;;
esac
printf 'bootstrap: %s\n' "$architecture"
for shell in sh zsh fish; do
    if ! command -v "$shell" >/dev/null 2>&1; then
        printf 'MISSING shell: %s\n' "$shell"
        failures=$((failures + 1))
        continue
    fi
    for program in claude codex grok kk fish fish_indent fish_key_reader coreutils fastfetch; do
        option=--version
        [ "$program" = kk ] && option=--self-test
        printf '\n==> %s -> %s %s\n' "$shell" "$program" "$option"
        "$shell" -c "$program $option"
        result=$?
        printf 'exit status: %s\n' "$result"
        [ "$result" -eq 0 ] || failures=$((failures + 1))
    done
done
printf '\nfailed checks: %s\n' "$failures"
[ "$failures" -eq 0 ]
