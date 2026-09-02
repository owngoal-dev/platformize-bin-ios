---
name: platformize-bin-ios
description: Port an upstream command-line tool (C/CMake, Rust/Cargo, …) to jailbroken iOS and ship it as a packaging-only repo that builds one arm64 binary and packages it for both roothide (iphoneos-arm64e) and rootless (iphoneos-arm64) bootstraps, releases via GitHub Actions, and is picked up by the OwnGoalPackages APT repo. Use when asked to "build X for jailbroken iOS", "package X like codex/grok/fastfetch", "make X work on rootless and roothide", or to add a tool to owngoalpackages.
---

# platformize-bin-ios

Turn an upstream CLI into `wiki.qaq.<program>_<ver>_iphoneos-arm64{,e}.deb`, the way
`OwnGoalStudio/{codex,grok,fastfetch}` do it. Reference implementations:
`../codex` and `../grok` (Rust), `../fastfetch` (C/CMake). Read one before starting.

## The contract (do not bend these)

- **Packaging repo, not a fork.** No upstream source is committed. `Configuration/upstream.env`
  pins a full commit sha; `patches/NNNN-*.patch` are applied to a pristine checkout by
  `Scripts/prepare-source.sh`. Small, single-purpose patches, generated with `git diff`.
- **One arm64 binary, two packages.** `iphoneos-arm64` = rootless (`/var/jb` prefix),
  `iphoneos-arm64e` = roothide (unprefixed tree, dpkg drops it into the randomized jbroot).
  The architecture field names the *layout*, never the CPU. Never build an arm64e slice.
- **No bootstrap path hardcoded in patched source.** Derive the bootstrap from the executable's
  own path (`<bootstrap>/usr/bin/<program>`), then probe `/var/jb`, then `/`. Prefix
  substitution (`@PREFIX@`) happens only in packaging (launcher scripts), never in code.
- **No libvroot.** The binary talks to libSystem directly. Path derivation replaces vroot.
- **Version lives in `Configuration/version.txt` only.** `X.Y.Z` = upstream's version;
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
- **Review for sensitive information before every upload or publish.** `Scripts/check-sensitive.sh`
  (in the template) scans tracked files, the staged package tree and the finished `.deb`s for
  credentials, private keys, home/scratch paths, device UDIDs, IP addresses and e-mail addresses.
  It is wired into `make check`, `package-deb.sh` and the Release workflow; run it by hand on
  anything else you are about to push (`Scripts/check-sensitive.sh <dir>`). A deliberate public
  value goes on its allowlist; never loosen a rule. Never paste a device hostname, serial, UDID
  or LAN address into docs, notes, commit messages or release bodies.

## Workflow

1. **Read the siblings.** `cat ../codex/AGENTS.md ../grok/AGENTS.md`; skim their `Scripts/`.
2. **Probe-build upstream first, in scratch.** Clone the latest stable tag, then:
   - CMake: `cmake -S src -B probe -G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
     -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_SYSROOT=iphoneos` and `ninja -k 0` to collect
     *every* failing file at once. Isolate pkg-config: `PKG_CONFIG_LIBDIR=<empty dir>`.
   - Cargo: `cargo build --release --target aarch64-apple-ios` with `SDKROOT` and
     `IPHONEOS_DEPLOYMENT_TARGET` exported (see `template/Scripts/build-ios.cargo.sh`).
3. **Triage each failure into one of three buckets** (see "iOS porting playbook").
4. **Iterate in the scratch checkout** (it is a git repo): edit, rebuild, until it links. Then
   `git add -A && git diff --cached -- <paths> > patches/000N-*.patch`, grouped by purpose.
5. **Instantiate the repo** from `template/` (see "Template"), point `upstream.env` at the
   sha, run `make check`, `make debs`. Both debs must come out of one build.
6. **Inspect the binary**: `vtool -show-build` says `platform IOS`, `lipo -archs` = arm64,
   `otool -L` only `/usr/lib` + `/System/Library/Frameworks`, and `nm -m | grep 'weak external'`
   lists every symbol newer than the deployment target — each must be null-checked in source.
7. **Device smoke test** if a device is attached: `make install` (runs `--version` and a real run).
8. **Review before publishing**: `make check` (runs `Scripts/check-sensitive.sh` on every
   tracked file and verifies the `CLAUDE.md` symlink), then
   `Scripts/check-sensitive.sh build/Packages/*.deb` on the exact assets you are about to
   upload. Read the diff once yourself for anything the regexes cannot know is private. Stop on
   any hit; nothing goes out until it is clean.
9. **Publish**: commit; `gh repo create OwnGoalStudio/<program> --public --source . --push`;
   enable Pages from `main:/docs` (`gh api -X POST repos/OwnGoalStudio/<program>/pages
   -f 'source[branch]=main' -f 'source[path]=/docs'`); `git tag vX.Y.Z && git push origin vX.Y.Z`;
   `gh release create vX.Y.Z --notes-file <(Scripts/release-notes.sh vX.Y.Z) build/Packages/*.deb
   build/Packages/SHA256SUMS` (the Release workflow re-uploads with `--clobber`, so a local
   release first is fine and removes the wait). Confirm `gh run list` shows Release green.
10. **Add to OwnGoalPackages** `manifest.json` (`repository` + `architectures`), commit, push,
    confirm its "Build and Deploy APT Repository" run goes green.
11. **Report**: what works, what is `nosupport`, whether the device test ran.

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
cp -R ~/Desktop/platformize-bin-ios/template/ <repo>/ && cd <repo>
mv Packaging/PROGRAM.entitlements Packaging/<program>.entitlements
# CMake project:  mv Scripts/build-ios.cmake.sh Scripts/build-ios.sh; rm Scripts/build-ios.cargo.sh Configuration/upstream.cargo.env
# Cargo project:  mv Scripts/build-ios.cargo.sh Scripts/build-ios.sh; mv Configuration/upstream.cargo.env Configuration/upstream.env; rm Scripts/build-ios.cmake.sh
chmod +x Scripts/*.sh
grep -rn 'fastfetch' makefile Scripts Packaging Configuration .github docs manifest.json   # every hit is a rename or a rewrite
```

Then edit, in this order: `Configuration/upstream.env` (repo, sha, PROGRAM), `version.txt`,
the `wiki.qaq.<program>` default in `makefile`, `package-deb.sh`, `install-device.sh`,
`release-notes.sh`; `Packaging/DEBIAN/control`; `Packaging/release-notes.md`; the
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
