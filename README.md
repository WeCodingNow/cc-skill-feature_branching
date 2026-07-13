# feature-branching

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills) that
codifies a specific git topology: agent work happens in a worktree on its own
branch, finished work lands on a shared `dev` integration branch by rebase +
fast-forward, and `main` only ever advances through a separate, deliberate
human promotion.

See [`SKILL.md`](./SKILL.md) for the actual rules and reasoning Claude
follows; this file is just about installing and using the skill itself.

## Injected git state & permissions

On load the skill injects a snapshot of the current git state (branch,
worktrees, whether `dev` exists, dirty tree) via
[dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context),
so Claude orients before proposing a worktree/commit/land step. Its
`allowed-tools` frontmatter auto-approves **only** the read-only git commands
that snapshot uses (`git branch`/`worktree`/`status`/`rev-parse`) while the
skill is active — deliberately *not* `git commit`/`reset`/`push`, which stay
behind normal permission prompts, consistent with the "never touch `main`"
rule.

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
scripts/drop-specs.sh             - remove a branch's .spec/ in one commit, after any promotion/inbox, before landing
scripts/list-spec-inbox.sh        - print .spec-inbox/ entries with their frontmatter description (or a warning if missing)
```

`.spec/` isn't the only ephemeral-spec location this skill knows about —
unconsumed specs (research being the common case) can also live in
`.spec-inbox/`, which is tracked on `dev` itself rather than dropped
before landing. Every spec file carries a frontmatter `description:` from
creation, so `land-to-dev.sh` can list `.spec-inbox/` entries by
description (not just filename) as a landing-time nudge. See `SKILL.md`'s
"Ephemeral specs" section for the full create/promote/inbox/drop story.

## Why a script for landing, but not for starting or committing

Rebasing a branch onto `dev` and fast-forwarding `dev` to match is
mechanical and easy to get subtly wrong under time pressure (e.g. rebasing
in the wrong direction rewrites `dev`'s own history) — a script that
refuses to do anything but a genuine fast-forward removes that risk
entirely. Deciding *when* a worktree branch is done, resolving rebase
conflicts, and writing the actual commit message are judgment calls —
those stay as instructions in `SKILL.md` for the agent to reason about.
