# platformize-bin-ios

A [Claude Code](https://claude.com/claude-code) skill that ports an upstream
command-line tool to **jailbroken iOS** and ships it the way OwnGoal Studio
does: one arm64 build, packaged for both **roothide** and **rootless**
bootstraps, released from GitHub Actions, and served by the
[OwnGoal Studio APT repository](https://github.com/OwnGoalStudio/OwnGoalPackages).

It is the distilled procedure behind
[codex](https://github.com/OwnGoalStudio/codex),
[grok](https://github.com/OwnGoalStudio/grok) and
[fastfetch](https://github.com/OwnGoalStudio/fastfetch): what is fixed by
contract, what breaks when you cross-compile against the iPhoneOS SDK, and
what a command-line process can and cannot do on a device.

## What you get

| path | what it is |
| --- | --- |
| `SKILL.md` | the skill: the packaging contract, a step-by-step workflow, and an iOS porting playbook (header shim, SDK traps, IOKit/Metal/MobileGestalt facts learned on real devices) |
| `template/` | a ready-to-copy packaging repo: `makefile`, `scripts/` for CMake and Cargo projects, `packaging/`, GitHub workflows (release + daily upstream follow), Pages redirect, package manifest |
| `template/scripts/rebase-patches.sh` | `make rebase-patches REF=<sha>`: re-targets `patches/` at a new upstream commit when the daily upstream follow stops applying, lists the rejects to fix by hand, then rewrites and re-verifies the patch set |
| `AGENTS.md` (`CLAUDE.md` links to it) | notes for agents working on this repository |

## Install

```sh
git clone https://github.com/OwnGoalStudio/platformize-bin-ios ~/.claude/skills/platformize-bin-ios
```

Then ask Claude Code to "build X for jailbroken iOS" or "package X like
codex/grok/fastfetch". The skill triggers on those phrases and on "add X to
owngoalpackages".

## The contract in one screen

- A packaging repo, never a fork: pinned upstream sha + `patches/`.
- One arm64 binary; `iphoneos-arm64` is the rootless layout (`/var/jb`),
  `iphoneos-arm64e` is roothide (unprefixed). The architecture names the
  layout, not the CPU.
- No bootstrap path hardcoded in source; derive it from the executable's own
  path. No libvroot.
- Sign with `ldid` and the three entitlements that make a CLI work on a
  jailbroken device; test by installing, never by copying a binary over.
- `CLAUDE.md` is a symlink to `AGENTS.md`.
- Review for sensitive information before every upload or publish by having
  an agent read the diff, the payload and `strings` of the binary. No scanner.
- Release first, then add to the APT manifest; its build fails otherwise.
- Every repo follows upstream daily and packages only the newest stable
  version; when a patch stops applying, `make rebase-patches REF=<sha>`.

## Using the template

```sh
cp -R template/ <repo>/ && cd <repo>
mv packaging/PROGRAM.entitlements packaging/<program>.entitlements
# CMake:  mv scripts/build-ios.cmake.sh scripts/build-ios.sh && rm scripts/build-ios.cargo.sh configuration/upstream.cargo.env
# Cargo:  mv scripts/build-ios.cargo.sh scripts/build-ios.sh && mv configuration/upstream.cargo.env configuration/upstream.env && rm scripts/build-ios.cmake.sh
chmod +x scripts/*.sh
grep -rn fastfetch makefile scripts packaging configuration .github docs manifest.json   # every hit is a rename
make check
```

`SKILL.md` lists the exact edits in order.

## License

MIT.
