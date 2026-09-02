# platformize-bin-ios — Agent Notes

This repository is a Claude Code skill (`SKILL.md`) plus the repo template it
instantiates (`template/`). It is documentation and scaffolding; there is no
build here.

## Hard rules

- **`SKILL.md` is the source of truth.** `README.md` summarises it for
  humans; when they disagree, fix `README.md`.
- **`template/` mirrors the live packaging repos.** It is the generic part
  of [OwnGoalStudio/fastfetch](https://github.com/OwnGoalStudio/fastfetch)
  (scripts, makefile, packaging, workflows) with the Cargo variants from
  [grok](https://github.com/OwnGoalStudio/grok). When a script changes in a
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
