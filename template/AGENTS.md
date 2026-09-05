# PROGRAM — Agent Notes

[PROGRAM](https://github.com/UPSTREAM_OWNER/UPSTREAM_REPO) — one line on what
it is — built for jailbroken iOS 15+ and installed as `PROGRAM`, for both
**roothide** and **rootless** bootstraps.

This repository holds **no application source**. It fetches upstream at a
pinned commit, applies `patches/`, cross-compiles for iOS, and packages.
Everything runs through `scripts/`, so CI and a local checkout execute the
same code.

## Hard rules

- **Not a fork.** Never vendor upstream source here. Every change to it is a
  patch in `patches/`, applied by `scripts/prepare-source.sh` to a fresh
  checkout of `UPSTREAM_REF`. Keep patches small and single-purpose.
- **`UPSTREAM_REF` is a full commit sha**, not a branch. Bump with
  `make bump-upstream REF=…`.
- **One arm64 binary backs both packages.** arm64 runs on every arm64e device
  and the reverse is not true. The two `.deb` architectures name a *bootstrap
  layout*, not a CPU: `iphoneos-arm64` is rootless, `iphoneos-arm64e` is
  roothide. Never build an arm64e slice for the "arm64e" package. Aggregate
  release targets build the payload once, package it twice, and checksum only
  the two exact current-version outputs.
- **Never hardcode a bootstrap path in patched source.** Derive the bootstrap
  from the executable's own path, then probe `/var/jb`, then `/`. Prefix
  substitution (`@PREFIX@`) belongs in packaging, not in code.
- **Versions live in `configuration/version.txt` only.** `X.Y.Z` tracks
  upstream's version; `X.Y.Z-N` is a packaging-only respin.
- **Evaluate official libvroot first for bootstrap-style ports.** Use it only in
  the RootHide package when all path consumers share that view. Native or mixed
  runtimes may retain physical paths with a documented reason; rootless does not
  load the RootHide runtime.
- **`CLAUDE.md` is a symlink to `AGENTS.md`**, never a file of its own. One
  set of notes, two names; `make check` enforces it.
- **Review for sensitive information before anything is uploaded or
  published.** This is a reading job, not a regex. Before a push, a tag or
  a release, have an agent (a subagent is fine) read the diff, the staged
  package tree and `strings` of the built binary for credentials, private
  keys, home or scratch paths, device identifiers and addresses. Nothing
  goes out until that read comes back clean. There is deliberately no
  script for this.
- **Published packages come from the Release workflow only.** Local
  `make debs` must keep working, to prove a build and to `make install` on a
  device, but a `.deb` built on a laptop is never uploaded or attached to a
  release: push the tag and let CI build, sign, review and publish.

## How the iOS port works

(Describe each patch in `patches/` in one paragraph: what upstream assumed,
what iOS lacks, what the patch does instead. Name the detectors or features
that are intentionally unsupported on iOS.)

## Layout

```
configuration/upstream.env   pinned ref, program name, iOS floor
configuration/version.txt    package version
patches/NNNN-*.patch         applied in sorted order to a pristine checkout
packaging/DEBIAN/control     control template (@PLACEHOLDER@ substituted)
packaging/PROGRAM.entitlements  what the signed binary carries, and why
packaging/release-notes.md   GitHub Release body template
scripts/prepare-source.sh    fetch + patch (idempotent, stamped)
scripts/rebase-patches.sh    re-target patches/ at a new upstream sha
scripts/build-ios.sh         cross-compile, verify Mach-O, assemble payload
scripts/package-deb.sh       stage + ldid + dpkg-deb + verify
scripts/install-device.sh    install over SSH and smoke-test (dev only)
build/                       everything generated; not source
```

## Build & verify

- `make check` — script syntax, config sanity, patch set, packaging inputs,
  `CLAUDE.md` link
- `make source` — fetch + patch; fails loudly if a patch no longer applies
- `make rebase-patches REF=<sha>` — when `make source` or `Follow upstream`
  fails on a patch: fuzz-applies `patches/` onto `<sha>` in `build/rebase` and
  lists the `*.rej`. Fix those by hand in `build/rebase` (usually reflowed
  comments), delete the `.rej`, rerun with `WRITE=1` to rewrite and re-verify
  `patches/`, then move the pin (`scripts/follow-upstream.sh`) and `make check`.
- `make build` — cross-compile and verify the Mach-O is iOS
- `make debs` — both packages plus `SHA256SUMS`; what CI releases
- `make install` — install on an attached device and smoke-test. Over USB:
  `iproxy 4422:2222 &`

Test by installing, never by copying a binary onto `/var/mobile`. A copied
binary runs with its entitlements ignored (trustcache never saw it).

## The OwnGoalPackages contract

A non-draft, non-prerelease tag `vX.Y.Z`; assets whose names end in
`iphoneos-arm64.deb` / `iphoneos-arm64e.deb`; a `SHA256SUMS` of bare names.

`Follow upstream` runs every day at 00:00 UTC: pin to the newest stable
upstream release, `make source` to prove `patches/` still apply, then commit
and tag `vX.Y.Z` as `bot <bot@owngoal.dev>` and dispatch `Release` on that
tag (`gh workflow run release.yml --ref vX.Y.Z`): a tag pushed with the
workflow's own token never fires a push-triggered workflow, and
`workflow_dispatch` is the documented exception. OwnGoalPackages fetches the
release at 04:00 UTC.

## RootHide signing and launcher checks

RootHide's official Developer README requires both
`com.apple.private.security.storage.AppBundles` and
`com.apple.private.security.storage.AppDataContainers`, in addition to the
platform and no-sandbox entitlements. Keep these in the executable signature
and verify the extracted signature after packaging; a correct package layout
alone does not establish access to RootHide's app-container installation path.
Source: https://github.com/roothide/Developer/blob/main/README.md

For payloads that do not use vroot, the launcher exports physical bootstrap
PATH, SHELL and default CA/browser paths. Preserve explicit CA/browser settings
and already physical or custom SHELL paths. Host launcher tests simulate the
path boundary and verify argv/exit status; they do not prove that iOS loads the
binary. Test the installed package from both zsh and fish on a RootHide device.
Do not add vroot to a payload while retaining a launcher that exports physical
paths: the filesystem view must remain consistent across the boundary.
