---
name: platformize-bin-ios
description: Port an upstream command-line tool (C/CMake, Rust/Cargo, …) to jailbroken iOS and ship it as a packaging-only repo that builds one arm64 binary and packages it for both roothide (iphoneos-arm64e) and rootless (iphoneos-arm64) bootstraps, releases via GitHub Actions, and is picked up by the OwnGoalPackages APT repo. Use when asked to "build X for jailbroken iOS", "package X like codex/grok/fastfetch", "make X work on rootless and roothide", or to add a tool to owngoalpackages.
---

# platformize-bin-ios

Turn an upstream CLI into `wiki.qaq.<program>_<ver>_iphoneos-arm64{,e}.deb`, the way
`OwnGoalStudio/{codex,grok,fastfetch}` do it. Reference implementations:
`../codex` and `../grok` (Rust), `../fastfetch` (C/CMake). Read one before starting.

## The contract (do not bend these)

- **Packaging repo, not a fork.** No upstream source is committed. `configuration/upstream.env`
  pins a full commit sha; `patches/NNNN-*.patch` are applied to a pristine checkout by
  `scripts/prepare-source.sh`. Small, single-purpose patches, generated with `git diff`.
- **One arm64 binary, two packages.** `iphoneos-arm64` = rootless (`/var/jb` prefix),
  `iphoneos-arm64e` = roothide (unprefixed tree, dpkg drops it into the randomized jbroot).
  The architecture field names the *layout*, never the CPU. Never build an arm64e slice.
- **No bootstrap path hardcoded in patched source.** Derive the bootstrap from the executable's
  own path (`<bootstrap>/usr/bin/<program>`), then probe `/var/jb`, then `/`. Prefix
  substitution (`@PREFIX@`) happens only in packaging (launcher scripts), never in code.
- **No libvroot.** The binary talks to libSystem directly. Path derivation replaces vroot.
- **Version lives in `configuration/version.txt` only.** `X.Y.Z` = upstream's version;
  `X.Y.Z-N` = packaging respin. `prepare-source.sh` should refuse a mismatch with upstream.
- **Sign with ldid + entitlements**: `platform-application`, `com.apple.private.security.no-sandbox`,
  `com.apple.private.security.container-required = false` (explicit false; absence is not the same).
  Add `com.apple.developer.kernel.extended-virtual-addressing` only for V8-class address cages.
- **Test by installing** (`make install` over `iproxy 4422:2222`), never by copying a binary to
  `/var/mobile`: a copied binary runs with entitlements ignored. If no device is attached
  (`idevice_id -l` empty), say so in the report; do not claim it runs.
- **OwnGoalPackages contract**: non-draft, non-prerelease tag `vX.Y.Z`; assets ending in
  `iphoneos-arm64.deb` / `iphoneos-arm64e.deb`; `SHA256SUMS` of bare names. The APT build
  *fails* if a manifest entry has no release, so create the release before editing the manifest.
- **`CLAUDE.md` is a symlink to `AGENTS.md`** (`ln -s AGENTS.md CLAUDE.md`), never a file.
  `make check` enforces it.
- **The make file is `makefile`, lowercase** (GNU make looks for `GNUmakefile`, `makefile`,
  `Makefile` in that order). Every OwnGoal repo uses the same spelling; keep it.
- **Directories are lowercase, single words**: `configuration/`, `packaging/`, `scripts/`,
  `patches/`, `docs/`. Only `AGENTS.md`, `README.md`, `LICENSE` and the DEBIAN control
  directory keep their conventional case. macOS hides case mistakes; CI on Linux does not.
- **Review for sensitive information before every upload or publish, by reading.** There is
  deliberately no scanner script. Before a push, a tag or a release, have an agent (spawn a
  subagent) read the diff, the staged package tree and `strings` of the built binary for
  credentials, private keys, home or scratch paths, device identifiers, hostnames and
  addresses, and report. Nothing goes out until that read comes back clean. Never paste a
  device hostname, serial, UDID or LAN address into docs, notes, commit messages or release
  bodies. Cargo builds export `RUSTFLAGS=--remap-path-prefix=<src>=/src
  --remap-path-prefix=<scratch>=/build` so panic locations do not carry the build machine's
  directories; check upstream's `.cargo/config.toml` first, the variable replaces any
  `[target.aarch64-apple-ios] rustflags`.
- **Every repo follows upstream daily and packages only the newest stable version.**
  `Follow upstream` runs at 00:00 UTC, pins the newest `X.Y.Z`, proves `patches/` apply,
  commits, tags `vX.Y.Z` and dispatches `Release` on the tag
  (`gh workflow run release.yml --ref vX.Y.Z`, with `actions: write`); a tag pushed with the
  workflow's own token never fires a push-triggered workflow. OwnGoalPackages fetches releases
  at 04:00 UTC. A failed `Follow upstream` run means a patch stopped applying: see
  "When Follow upstream fails".
- **Published packages come from the Release workflow only.** Local `make debs` must keep
  working (it is how you prove a build and `make install` on a device), but nothing built on
  a laptop is uploaded: push the tag and let CI build, sign, review and publish.

## Workflow

1. **Read the siblings.** `cat ../codex/AGENTS.md ../grok/AGENTS.md`; skim their `scripts/`.
2. **Probe-build upstream first, in scratch.** Clone the latest stable tag, then:
   - CMake: `cmake -S src -B probe -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
     -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_SYSROOT=iphoneos` and `ninja -k 0` to collect
     *every* failing file at once. Isolate pkg-config: `PKG_CONFIG_LIBDIR=<empty dir>`.
   - Cargo: `cargo build --release --target aarch64-apple-ios` with `SDKROOT` and
     `IPHONEOS_DEPLOYMENT_TARGET` exported (see `template/scripts/build-ios.cargo.sh`).
3. **Triage each failure into one of three buckets** (see "iOS porting playbook").
4. **Iterate in the scratch checkout** (it is a git repo): edit, rebuild, until it links. Then
   `git add -A && git diff --cached -- <paths> > patches/000N-*.patch`, grouped by purpose.
5. **Instantiate the repo** from `template/` (see "Template"), point `upstream.env` at the
   sha, run `make check`, `make debs`. Both debs must come out of one build.
6. **Inspect the binary**: `vtool -show-build` says `platform IOS`, `lipo -archs` = arm64,
   `otool -L` only `/usr/lib` + `/System/Library/Frameworks`, and `nm -m | grep 'weak external'`
   lists every symbol newer than the deployment target — each must be null-checked in source.
7. **Device smoke test** if a device is attached: `make install` (runs `--version` and a real run).
8. **Review before publishing**: `make check`, then spawn a subagent to read `git diff`,
   the payload tree and `strings build/ios-arm64/payload/<program>` for anything private
   (credentials, home or scratch paths, device identifiers, addresses) and report back. Stop
   on any finding; nothing goes out until it is clean.
9. **Publish**: commit; `gh repo create OwnGoalStudio/<program> --public --source . --push`;
   enable Pages from `main:/docs` (`gh api -X POST repos/OwnGoalStudio/<program>/pages
   -f 'source[branch]=main' -f 'source[path]=/docs'`); `git tag vX.Y.Z && git push origin vX.Y.Z`.
   The Release workflow builds that tag and creates the GitHub Release. **Every published
   package comes out of the workflow**: never `gh release create` or upload a `.deb` built on
   your machine; local `make debs` exists to prove the build and to `make install` on a device.
   Watch `gh run watch` until Release is green; only then move on.
10. **Add to OwnGoalPackages** `manifest.json` (`repository` + `architectures`), commit, push,
    confirm its "Build and Deploy APT Repository" run goes green.
11. **Report**: what works, what is `nosupport`, whether the device test ran.

## When Follow upstream fails

Upstream moved and a patch no longer applies. The run's log names the patch and the new sha.
Expect this often for fast-moving projects; it is a 10-minute job, not a re-port.

1. `make rebase-patches REF=<new sha>` — checks the sha out into `build/rebase` and applies
   `patches/` with fuzz. Offsets are fine. For each `REJECTS` line, read the `.rej`: almost
   always a doc comment that upstream reflowed around code that still applies.
2. Fix each reject by hand in `build/rebase` (edit the file, then delete the `.rej`). Diff the
   original patch against the new upstream text; keep the same words in the new layout.
3. `make rebase-patches REF=<new sha> WRITE=1` — rewrites every patch from `build/rebase` (one
   patch per purpose, one file per patch owner, no `index` lines) and re-applies them from a
   clean checkout to prove it.
4. `scripts/follow-upstream.sh` moves the pin and version and runs `make source`; then
   `make check`, and `make debs` if the build is affordable locally (Cargo: minutes; V8: hours,
   let CI do it).
5. Also look for a changed build contract: a version placeholder that became a committed
   version (codex 0.152), a helper binary version bump, a new `cfg` split. Fix the script, not
   the symptom, and record it in `AGENTS.md`.
6. Commit as "Rebase patches onto X.Y.Z", push, tag `vX.Y.Z` yourself (a human-pushed tag fires
   `Release` directly), and watch `gh run list` until Release is green. `Follow upstream` then
   finds the tag and does nothing until the next upstream version.

## iOS porting playbook

The iPhoneOS SDK *omits headers* for many APIs that iOS *does export*. Sort each compile error:

| Symptom | Bucket | Fix |
| --- | --- | --- |
| `'libproc.h' / 'net/route.h' / 'IOKit/ps/...' file not found` and the symbol **is** in the SDK `.tbd` (`grep _Symbol $SDK/System/Library/Frameworks/X.framework/X.tbd`) | header missing, API present | Build-script shim: symlink only the missing headers from the macOS SDK into `<scratch>/sdk-shim` and pass `-isystem <shim>`. Only what the iOS SDK lacks goes in, so the iOS SDK's declarations keep winning. Whole-IOKit rule: link every top-level entry of the macOS IOKit `Headers/` that the iOS one lacks. |
| `'X' is unavailable: not available on iOS`, or framework has no iOS `.tbd` (AppKit, CoreWLAN, IOBluetooth, CoreAudio HAL, OpenGL/OpenCL, CoreDisplay, SCDynamicStore, NSAppleScript, KextManager, `wordexp`) | API absent | Swap the source file for the project's `_nosupport` / portable variant in the build system (CMake `if(IOS) list(REMOVE_ITEM …) list(APPEND …)`; Cargo `cfg(target_os = "ios")`), or a `#if TARGET_OS_IPHONE` guard in a shared file. Never link a macOS framework. |
| API exists on iOS but the macOS answer is wrong (OS name/version, display, package manager, CPU/GPU name, chassis) | needs iOS answer | New `_ios` file or a `TARGET_OS_IPHONE` branch. Known good sources: `SystemVersion.plist` + `hw.machine` for OS; MobileGestalt `main-screen-{width,height,scale,pitch}` (dlopen `/usr/lib/libMobileGestalt.dylib`, unprotected keys) for display; `<bootstrap>/var/lib/dpkg/status` for packages; `IODeviceTree:/product/product-name` for host name; `IODeviceTree:/chosen/chip-id` (0x8027 = t8027 = A12X/Z) for the SoC name, because `machdep.cpu.brand_string` is the literal "Apple processor"; GPU = the `AGXAccelerator` IORegistry service (`GPUConfigurationVariable/num_cores`, `PerformanceStatistics`, `pmgr` clocks) — there is no `IOAccelerator` class and `MTLCreateSystemDefaultDevice()` is **nil** for a CLI process. Memory, battery (`AppleSmartBattery`), power adapter, disks compile unchanged. |

Two SDK traps, always:

- **New SDK, old device.** `check_function_exists(pipe2)` says yes with the iOS 27 SDK; no
  device before 27 has it → dyld abort. Pin such checks (`-DHAVE_PIPE2=0`). Any symbol newer
  than `MIN_IOS` is weak-linked and NULL at runtime; the build script must print
  `nm -m … | grep 'weak external'` and every entry must be guarded in source.
- **CMake makes `.app` bundles for iOS.** Pass `-DCMAKE_MACOSX_BUNDLE=OFF`.
- **Objective-C methods newer than `MIN_IOS`** have no weak symbol — they crash with
  unrecognized selector. Guard with `if (@available(iOS N, *))`; never silence
  `-Wunguarded-availability-new` with a pragma.

Device-side probing beats guessing: compile a 30-line probe (`xcrun --sdk iphoneos clang -arch
arm64 -miphoneos-version-min=15.0 …`), `ldid -S<entitlements> -Cadhoc` it, `scp` to `/tmp`, run
over SSH. `ioreg` on the bootstrap may print nothing; IOKit from a platform-signed probe works.

Rust-specific (from codex/grok): `SHELL` from a vroot parent lies; probe `.jbroot/bin`,
`/var/jb/bin`, `/bin` for the shell. Disable self-updaters; point users at the package manager.
Skip desktop-only crates behind `cfg` rather than enabling another OS's backend.

Logo/branding: when the tool picks assets by OS id, set `idLike = macos` (or equivalent
fallback) so an `ios` id still resolves to the Apple asset.

## Template

`template/` is the fastfetch repo minus its patches. Instantiate:

```sh
cp -R ~/.claude/skills/platformize-bin-ios/template/ <repo>/ && cd <repo>   # or wherever this skill is checked out
mv packaging/PROGRAM.entitlements packaging/<program>.entitlements
# CMake project:  mv scripts/build-ios.cmake.sh scripts/build-ios.sh; rm scripts/build-ios.cargo.sh configuration/upstream.cargo.env
# Cargo project:  mv scripts/build-ios.cargo.sh scripts/build-ios.sh; mv configuration/upstream.cargo.env configuration/upstream.env; rm scripts/build-ios.cmake.sh
chmod +x scripts/*.sh
grep -rn 'fastfetch' makefile scripts packaging configuration .github docs manifest.json   # every hit is a rename or a rewrite
```

Then edit, in this order: `configuration/upstream.env` (repo, sha, PROGRAM), `version.txt`,
the `wiki.qaq.<program>` default in `makefile`, `package-deb.sh`, `install-device.sh`,
`release-notes.sh`; `packaging/DEBIAN/control`; `packaging/release-notes.md`; the
`follow-upstream.sh` tag regex (`^X.Y.Z$` vs `^rust-vX.Y.Z$`); `build-ios.sh`'s configure
flags and the payload verification paths; `install-device.sh`'s smoke commands; the workflow
tool-install step (`cmake ninja` vs `rust-toolchain`). Write `AGENTS.md`/`README.md` in the
sibling style: hard rules, how the port works, layout, build & verify, the OwnGoalPackages
contract. `docs/index.html` and `manifest.json` are the Pages redirect + package manifest.

`template/patches/example-0004-ios-bootstrap-config-dir.patch` shows the executable-path
bootstrap derivation to copy into any C tool that reads `/etc` or `/usr/share`.

## Output

A report that says, per module, works / nosupport / untested, the two deb names + digests,
the release URL, the OwnGoalPackages commit, and whether the device smoke test ran.
