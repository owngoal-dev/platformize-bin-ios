#!/usr/bin/env bash
#
# Pin this packaging repo to the newest stable fastfetch-cli/fastfetch X.Y.Z
# release, validate that patches/ still apply, and print what changed.
#
# Does not build debs or create a GitHub release. The scheduled workflow
# commits the pin and tags vX.Y.Z; release.yml turns that tag into packages.
# OwnGoalPackages picks up the newest non-preview release on its next run.
#
#   scripts/follow-upstream.sh           # rewrite configuration/ if newer
#   scripts/follow-upstream.sh --check   # exit 0 if already current
#   scripts/follow-upstream.sh --dry-run # print the candidate, change nothing
#   scripts/follow-upstream.sh --print   # one line: version sha tag

set -Eeuo pipefail

mode=apply
case "${1:-}" in
"" ) ;;
--check) mode=check ;;
--dry-run) mode=dry-run ;;
--print) mode=print ;;
-h | --help)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
*)
    echo "usage: $0 [--check|--dry-run|--print]" >&2
    exit 64
    ;;
esac

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../configuration/upstream.env
source "$repository_root/configuration/upstream.env"

: "${UPSTREAM_REPO:?}"
: "${UPSTREAM_REF:?}"

command -v gh >/dev/null || { echo "error: gh is not installed" >&2; exit 69; }
command -v python3 >/dev/null || { echo "error: python3 is not installed" >&2; exit 69; }

upstream_slug="${UPSTREAM_REPO#https://github.com/}"
upstream_slug="${upstream_slug%.git}"

current_version="$(tr -d '[:space:]' <"$repository_root/configuration/version.txt")"
current_upstream_version="${current_version%%-*}"

read -r upstream_version upstream_tag <<EOF
$(python3 - "$upstream_slug" <<'PY'
import json, re, subprocess, sys
slug = sys.argv[1]
payload = subprocess.check_output(
    ["gh", "api", f"repos/{slug}/releases?per_page=40"],
    text=True,
)
pat = re.compile(r"^(\d+\.\d+\.\d+)$")
for release in json.loads(payload):
    if release.get("draft") or release.get("prerelease"):
        continue
    match = pat.match(release.get("tag_name") or "")
    if match:
        print(match.group(1), match.group(0))
        sys.exit(0)
sys.exit(f"error: no stable X.Y.Z release on {slug}")
PY
)
EOF

[[ "$upstream_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: could not parse a stable X.Y.Z tag from $upstream_slug" >&2
    exit 65
}

ref_json="$(gh api "repos/$upstream_slug/git/ref/tags/${upstream_tag}")"
object_type="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["object"]["type"])' <<<"$ref_json")"
object_sha="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["object"]["sha"])' <<<"$ref_json")"
if [[ "$object_type" == "tag" ]]; then
    upstream_sha="$(gh api "repos/$upstream_slug/git/tags/${object_sha}" --jq .object.sha)"
else
    upstream_sha="$object_sha"
fi
[[ "$upstream_sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "error: could not resolve $upstream_tag to a commit" >&2
    exit 65
}

if [[ "$mode" == "print" ]]; then
    printf '%s %s %s\n' "$upstream_version" "$upstream_sha" "$upstream_tag"
    exit 0
fi

echo "current:  $current_version @ $UPSTREAM_REF"
echo "upstream: $upstream_version ($upstream_tag) @ $upstream_sha"

version_order="$(python3 - "$upstream_version" "$current_upstream_version" <<'PY'
import sys
candidate = tuple(map(int, sys.argv[1].split(".")))
current = tuple(map(int, sys.argv[2].split(".")))
print((candidate > current) - (candidate < current))
PY
)"
if (( version_order <= 0 )); then
    echo "no newer stable version than $current_upstream_version"
    exit 0
fi

if [[ "$upstream_sha" == "$UPSTREAM_REF" ]]; then
    echo "already pinned to $upstream_tag"
    exit 0
fi

if [[ "$mode" == "check" ]]; then
    echo "pin is behind $upstream_tag"
    exit 1
fi

if [[ "$mode" == "dry-run" ]]; then
    echo "dry-run: would pin $upstream_sha and set version $upstream_version"
    exit 0
fi

python3 - "$repository_root/configuration/upstream.env" "$upstream_sha" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
sha = sys.argv[2]
lines = []
replaced = False
for line in path.read_text().splitlines(keepends=True):
    if line.startswith("UPSTREAM_REF="):
        lines.append(f"UPSTREAM_REF={sha}\n")
        replaced = True
    else:
        lines.append(line)
if not replaced:
    raise SystemExit(f"{path} has no UPSTREAM_REF=")
path.write_text("".join(lines))
PY
printf '%s\n' "$upstream_version" >"$repository_root/configuration/version.txt"
echo "pinned UPSTREAM_REF=$upstream_sha"
echo "set version $upstream_version"

# Cheap validation: fetch + apply patches. Does not cross-compile.
make -C "$repository_root" source

echo "ready to tag v$upstream_version"
