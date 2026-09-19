#!/usr/bin/env bash
# Gate the common arm64 payload: no fork/exec, no set*id, no libvroot.
# Call this from build-ios.sh on the binary that will be packaged, not on
# PROGRAM.launcher.c (that file is the documented execv exception).
set -Eeuo pipefail

[[ "$#" -eq 1 ]] || { echo "usage: $0 <executable>" >&2; exit 64; }
executable="$1"
[[ -f "$executable" ]] || { echo "error: no such file: $executable" >&2; exit 66; }

symbols="$(nm -m "$executable")"
forbidden="$(grep -E 'external _+(fork|vfork|exec[lv][epP]*|fexecve)([ $]|$)' <<<"$symbols" || true)"
[[ -z "$forbidden" ]] || {
    echo "error: $executable carries fork/exec symbols:" >&2
    printf '%s\n' "$forbidden" >&2
    echo "posix_spawn is the one way to start a child; record an exception in AGENTS.md if a subcommand must keep one of these." >&2
    exit 65
}
if grep -qE '\(undefined\).*external _(setuid|seteuid|setreuid|setgid|setegid|setregid|setgroups|initgroups)( |$)' <<<"$symbols"; then
    echo "error: $executable imports a privilege-changing syscall" >&2
    exit 65
fi

while read -r dependency; do
    case "$dependency" in
    *libvroot*)
        echo "error: $executable links libvroot on the common build:" >&2
        echo "       $dependency" >&2
        echo "symredirect is RootHide-payload only; the common arm64 binary stays physical-path." >&2
        exit 65
        ;;
    esac
done < <(otool -L "$executable" | tail -n +2 | awk '{print $1}')

echo "==> no fork/exec, set*id or libvroot in $executable" >&2
