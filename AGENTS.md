# platformize-bin-ios — Agent Notes

This repository is a Claude Code skill (`SKILL.md`) plus the repo template it
instantiates (`template/`). It is documentation and scaffolding; there is no
build here.

## Hard rules

- **`SKILL.md` is the source of truth.** `README.md` summarises it for
  humans; when they disagree, fix `README.md`.
- **`template/` mirrors the live packaging repos.** It is the generic part
  of [owngoal-dev/fastfetch](https://github.com/owngoal-dev/fastfetch)
  (scripts, makefile, packaging, workflows) with the Cargo variants from
  [grok](https://github.com/owngoal-dev/grok). When a script changes in a
  live repo, port the change here in the same commit, and the other way
  round. Do not let the three repos and the template drift.
- **No ported binary may reach `fork()`.** A jailbroken CLI has the
  Objective-C runtime, Foundation and usually a thread or two loaded by the
  time it starts a child, and forking that is not safe on iOS. Every child
  goes through `posix_spawn()` or `execve()`. This is a *build gate*, not a
  review note: the port's `build-ios.sh` must reject a Mach-O that imports
  `_fork` or `_vfork`, and must audit the prepared source for what puts a
  program back on the fork path. In Rust that is `pre_exec` / `before_exec` /
  `uid` / `gid` / `groups` on a `std::process::Command` — any one of them makes
  `std` fall back to `fork()` + `exec()`; `CommandExt::exec()` is fine, it
  replaces the process image. In C it is `fork`, `vfork`, `daemon`, `system`
  and `popen`. Two ports to copy from:
  [fish](https://github.com/owngoal-dev/fish) rewrote its spawn path
  (`0001-ios-forkless-exec`); [coreutils](https://github.com/owngoal-dev/coreutils)
  cfg-guarded the one `pre_exec` and then *defined* `fork()` to fail with
  `EPERM` instead of importing it, so a regression cannot silently reach the
  real one. Prove it runs, not just links: build the same patched source for
  the host — `target_vendor = "apple"` is equally true there — and run the
  subcommands that spawn under `lldb` with breakpoints on `fork` and `vfork`.
- **Nothing escalates privilege.** A jailbroken CLI starts as `mobile`; children
  inherit that through the spawn and no tool should re-assume an identity. Gate
  the Mach-O on `setuid`, `seteuid`, `setreuid`, `setgid`, `setegid`,
  `setregid`, `setgroups` and `initgroups`, and drop the subcommand that needs
  them instead of shipping it broken — `coreutils` drops `chroot`, its only
  caller, which on iOS needs root regardless. Note that Rust's `std` links the
  credential calls into the child half of its fork path even when nothing calls
  them, so define those to `EPERM` alongside `fork()`. Dropping privilege is a
  different thing and stays: lowering one's own priority, `setpgid` to signal a
  child's process group.
- **`CLAUDE.md` is a symlink to `AGENTS.md`**, here and in `template/`.
  Never replace it with a file.
- **Review for sensitive information before anything is uploaded or
  published.** A reading job, not a regex: before every push, have an
  agent (a subagent is fine) read the diff for credentials, private keys,
  home or scratch paths, device identifiers and addresses. Device facts
  recorded in `SKILL.md` are generic (chip ids, IORegistry class names),
  never a serial, UDID, hostname or address.
- **Facts in the playbook come from a device or an SDK, not from memory.**
  Add a fact together with how it was observed (probe binary, `nm -m`,
  `.tbd` grep). Remove a fact when it stops being true.

## Layout

```
SKILL.md                     the skill: contract, workflow, iOS porting playbook
README.md                    human summary and install instructions
template/                    packaging repo scaffold (see SKILL.md "Template")
template/scripts/build-ios.cmake.sh   CMake projects
template/scripts/build-ios.cargo.sh   Cargo projects
template/patches/example-*   reference patches worth copying
```

## Verify

```sh
bash -n template/scripts/*.sh
test "$(readlink CLAUDE.md)" = AGENTS.md && test "$(readlink template/CLAUDE.md)" = AGENTS.md
```
