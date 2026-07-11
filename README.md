# feature-branching

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills) that
codifies a specific git topology: agent work happens in a worktree on its own
branch, finished work lands on a shared `dev` integration branch by rebase +
fast-forward, and `main` only ever advances through a separate, deliberate
human promotion.

See [`SKILL.md`](./SKILL.md) for the actual rules and reasoning Claude
follows; this file is just about installing and using the skill itself.

## Install

This repo *is* the skill — Claude Code loads a skill from a directory
containing a `SKILL.md`. To make it available globally, symlink it into your
skills directory:

```sh
ln -s /path/to/cc-skill-feature_branching ~/.claude/skills/feature-branching
```

## Requirements

- A repo that has (or wants) a local `dev` branch sitting between feature
  work and `main`. This skill doesn't create `dev` — that's a one-time
  repo-setup decision for a human.
- `bash` and standard git on `PATH`.

## Layout

```
SKILL.md                          - the skill itself: workflow, reasoning, when to use which script
scripts/land-to-dev.sh            - rebase the current worktree branch onto dev, then fast-forward dev
scripts/drop-specs.sh             - remove a branch's .specs/ in one commit, after any promotion, before landing
scripts/normalize-branch-name.sh - print <goal>/<source-branch, slashes replaced with dashes>
scripts/install-commit-msg-hook.sh - one-time per repo: symlinks hooks/commit-msg into .git/hooks
hooks/commit-msg                  - validates commit titles against Conventional Commits 1.0.0
```

## Why a script for landing, but not for starting or committing

Rebasing a branch onto `dev` and fast-forwarding `dev` to match is
mechanical and easy to get subtly wrong under time pressure (e.g. rebasing
in the wrong direction rewrites `dev`'s own history) — a script that
refuses to do anything but a genuine fast-forward removes that risk
entirely. Conventional Commits formatting is likewise a fixed, checkable
pattern, so it's a `commit-msg` hook rather than something to re-derive by
eye every commit. Deciding *when* a worktree branch is done, resolving
rebase conflicts, and writing the actual commit message are judgment calls
— those stay as instructions in `SKILL.md` for the agent to reason about.
