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

## Preferred ways

Not absolutes -- there are tools that genuinely cannot be written without these
-- but the default, and the thing to reach for first. Where a port ends up
needing one anyway, say so in its `AGENTS.md` and gate the rest.

### No `fork()`

`posix_spawn()`, and only `posix_spawn()`. By the time a jailbroken CLI starts
a child it has the Objective-C runtime, Foundation and usually a thread or two
loaded, and forking a process in that state is not safe on iOS.

`execve()` is not the fallback. Replacing the process image drops everything
the current process was trusted for -- its signed identity and entitlements do
not carry across, the new image has to satisfy AMFI on its own, and what it
inherits from the bootstrap's view of the filesystem is not the same thing the
caller had. It works often enough to look fine in a smoke test and then fails
somewhere specific. Spawn a child and wait for it.

What quietly puts a program back on the fork path:

- Rust: `pre_exec`, `before_exec`, `uid`, `gid` or `groups` on a
  `std::process::Command`. Any one of them makes `std` abandon `posix_spawn()`
  for `fork()` + `exec()`. `CommandExt::exec()` avoids the fork but is the
  `execve()` case above -- prefer spawning over it too.
- C: `fork`, `vfork`, `daemon`, `system`, `popen`, and `execve` family calls
  that replace the caller rather than a freshly spawned child.

Two shapes of fix, both in the wild:
[fish](https://github.com/owngoal-dev/fish) rewrote its spawn path
(`0001-ios-forkless-exec`); [coreutils](https://github.com/owngoal-dev/coreutils)
cfg-guarded the single `pre_exec` and then *defined* `fork()` to fail with
`EPERM` rather than importing it, so a regression cannot silently find the real
one.

Make it a build gate rather than a review note: reject a Mach-O that imports
`_fork` or `_vfork`, and audit the prepared source for the calls above. Gate
the `exec*` imports the same way -- and where a port keeps one, say which
subcommand and why in its own `AGENTS.md`, so the exception is recorded rather
than rediscovered. Then
prove it runs, not just links -- build the same patched source for the host,
where `target_vendor = "apple"` is equally true, and run the subcommands that
spawn under `lldb` with breakpoints on `fork` and `vfork`.

### No `set*id()`

Prefer inheriting. A jailbroken CLI starts as `mobile`, children inherit that
through the spawn, and a tool that re-assumes an identity is doing something
the bootstrap did not ask for. Gate the Mach-O on `setuid`, `seteuid`,
`setreuid`, `setgid`, `setegid`, `setregid`, `setgroups` and `initgroups`.

When a subcommand cannot work without them, prefer dropping that subcommand
over shipping it broken: `coreutils` drops `chroot`, its only caller, which on
iOS needs root regardless.

Watch for calls nothing asks for. Rust's `std` links the credential syscalls
into the child half of its fork path even when no code sets a uid, so define
those to `EPERM` alongside `fork()`.

*Dropping* privilege is a different thing and stays: lowering one's own
priority, `setpgid` to signal a child's process group.

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
