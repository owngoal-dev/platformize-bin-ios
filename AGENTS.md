# platformize-bin-ios — Agent Notes

This repository is a Claude Code skill (`SKILL.md`) plus the repo template it
instantiates (`template/`). It is documentation and scaffolding; there is no
build here.

## Hard rules

- **`SKILL.md` is the source of truth.** `README.md` summarises it for
  humans; when they disagree, fix `README.md`.
- **`template/` mirrors the live packaging repos.** It is the generic part
  of [OwnGoalStudio/fastfetch](https://github.com/OwnGoalStudio/fastfetch)
  (scripts, Makefile, packaging, workflows) with the Cargo variants from
  [grok](https://github.com/OwnGoalStudio/grok). When a script changes in a
  live repo, port the change here in the same commit, and the other way
  round. Do not let the three repos and the template drift.
- **`CLAUDE.md` is a symlink to `AGENTS.md`**, here and in `template/`.
  Never replace it with a file.
- **Review for sensitive information before anything is uploaded or
  published.** Run `template/Scripts/check-sensitive.sh .` from the root of
  this repository before every push. It refuses credentials, private keys,
  home and scratch paths, device identifiers, IP addresses and e-mail
  addresses outside the public maintainer domain. Device facts recorded in
  `SKILL.md` are generic (chip ids, IORegistry class names), never a serial,
  UDID, hostname or address.
- **Facts in the playbook come from a device or an SDK, not from memory.**
  Add a fact together with how it was observed (probe binary, `nm -m`,
  `.tbd` grep). Remove a fact when it stops being true.

## Layout

```
SKILL.md                     the skill: contract, workflow, iOS porting playbook
README.md                    human summary and install instructions
template/                    packaging repo scaffold (see SKILL.md "Template")
template/Scripts/build-ios.cmake.sh   CMake projects
template/Scripts/build-ios.cargo.sh   Cargo projects
template/Scripts/check-sensitive.sh   pre-publish review, wired into make check
template/patches/example-*   reference patches worth copying
```

## Verify

```sh
bash -n template/Scripts/*.sh
test "$(readlink CLAUDE.md)" = AGENTS.md && test "$(readlink template/CLAUDE.md)" = AGENTS.md
template/Scripts/check-sensitive.sh .
```
