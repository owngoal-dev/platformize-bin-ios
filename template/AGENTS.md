# PROGRAM — Agent Notes

[PROGRAM](https://github.com/UPSTREAM_OWNER/UPSTREAM_REPO) — one line on what
it is — built for jailbroken iOS 15+ and installed as `PROGRAM`, for both
**roothide** and **rootless** bootstraps.

This repository holds **no application source**. It fetches upstream at a
pinned commit, applies `patches/`, cross-compiles for iOS, and packages.
Everything runs through `Scripts/`, so CI and a local checkout execute the
same code.

## Hard rules

- **Not a fork.** Never vendor upstream source here. Every change to it is a
  patch in `patches/`, applied by `Scripts/prepare-source.sh` to a fresh
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
- **Versions live in `Configuration/version.txt` only.** `X.Y.Z` tracks
  upstream's version; `X.Y.Z-N` is a packaging-only respin.
- **Do not link libvroot.** The binary talks to libSystem directly.
- **`CLAUDE.md` is a symlink to `AGENTS.md`**, never a file of its own. One
  set of notes, two names; `make check` enforces it.
- **Review for sensitive information before anything is uploaded or
  published.** `Scripts/check-sensitive.sh` scans tracked files, the staged
  package tree and the finished `.deb`s for credentials, private keys, home
  and scratch paths, device identifiers, IP addresses and e-mail addresses.
  `make check`, `package-deb.sh` and the Release workflow all run it and
  stop on a hit. A deliberate public value goes on its allowlist; a rule is
  never loosened.

## How the iOS port works

(Describe each patch in `patches/` in one paragraph: what upstream assumed,
what iOS lacks, what the patch does instead. Name the detectors or features
that are intentionally unsupported on iOS.)

## Layout

```
Configuration/upstream.env   pinned ref, program name, iOS floor
Configuration/version.txt    package version
patches/NNNN-*.patch         applied in sorted order to a pristine checkout
Packaging/DEBIAN/control     control template (@PLACEHOLDER@ substituted)
Packaging/PROGRAM.entitlements  what the signed binary carries, and why
Packaging/release-notes.md   GitHub Release body template
Scripts/prepare-source.sh    fetch + patch (idempotent, stamped)
Scripts/build-ios.sh         cross-compile, verify Mach-O, assemble payload
Scripts/package-deb.sh       stage + ldid + dpkg-deb + verify
Scripts/check-sensitive.sh   pre-publish review of files, payload and .debs
Scripts/install-device.sh    install over SSH and smoke-test (dev only)
build/                       everything generated; not source
```

## Build & verify

- `make check` — script syntax, config sanity, patch set, packaging inputs,
  `CLAUDE.md` link, sensitive-information review
- `make source` — fetch + patch; fails loudly if a patch no longer applies
- `make build` — cross-compile and verify the Mach-O is iOS
- `make debs` — both packages plus `SHA256SUMS`; what CI releases
- `make install` — install on an attached device and smoke-test. Over USB:
  `iproxy 4422:2222 &`

Test by installing, never by copying a binary onto `/var/mobile`. A copied
binary runs with its entitlements ignored (trustcache never saw it).

## The OwnGoalPackages contract

A non-draft, non-prerelease tag `vX.Y.Z`; assets whose names end in
`iphoneos-arm64.deb` / `iphoneos-arm64e.deb`; a `SHA256SUMS` of bare names.

`Follow upstream` runs every Monday at 00:00 UTC: pin to the newest stable
upstream release, `make source` to prove `patches/` still apply, then commit
and tag `vX.Y.Z` as `bot <bot@owngoal.dev>`. `Release` builds that tag.
OwnGoalPackages fetches it at 04:00 UTC.
