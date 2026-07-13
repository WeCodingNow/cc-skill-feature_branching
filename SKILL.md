---
name: feature-branching
description: Enforces a worktree-per-branch git workflow with a `dev` integration branch sitting between feature work and `main` — creating worktrees off the right base, keeping commits atomic and buildable, and landing finished work onto `dev` via rebase + fast-forward (never a merge commit, never touching `main`). Use this whenever the user asks to start work on something new, create or set up a worktree, land/merge/integrate a branch onto dev, or asks whether a branch is "ready to merge" or "ready to land". Also trigger on "rebase my branch onto dev" or any mention of a dev/main branch split — even if the user doesn't name this workflow directly.
allowed-tools:
  - Bash(git branch *)
  - Bash(git worktree *)
  - Bash(git status *)
  - Bash(git rev-parse *)
  - Bash(git rebase dev)
  - Bash(echo *)
  - Bash(*/.claude/skills/feature-branching/scripts/list-spec-inbox.sh)

---

# Feature branching: worktree → dev → main

This skill codifies one specific git topology: all agent work happens in a
throwaway worktree on its own branch; finished work lands on `dev` (the
shared integration branch) by rebase + fast-forward; `main` only moves
through a separate, deliberate promotion that this skill never performs.

The reasoning behind each rule matters more than the rule itself — read
"Why this shape" before mechanically applying the steps below.

## Current git state

Current branch: !`git branch --show-current`

`dev` branch: !`git rev-parse --verify --quiet dev >/dev/null 2>&1 && echo present || echo "MISSING — this repo may not use the worktree → dev → main workflow"`

Worktrees:
!`git worktree list`

## Why this shape

- **Worktrees, not branch-switching in place**, so nothing you're doing can
  clobber whatever the human (or another agent) has checked out in the main
  working directory, and so several agents can work concurrently without
  fighting over one working tree.
- **`dev` as a landing pad, not `main` directly**, so agents can integrate
  their own finished work without a review gate, while `main` stays a
  deliberately-curated history that only advances through a human decision.
  Never rebase, fast-forward, or commit directly to `main`.
- **Rebase + fast-forward, never a merge commit**, so `dev`'s history stays
  linear and easy to read. Concretely this means: your feature branch's
  commits get replayed onto *dev's* current tip (your branch's hashes
  change, which is fine — it's disposable), and `dev` itself only ever
  fast-forwards (its commit hashes never change). That asymmetry is
  intentional: `dev` must stay stable enough that other worktrees can
  rebase against it without their history being rewritten out from under
  them. Doing it the other way around (checking out `dev` and rebasing
  *it* onto your feature branch) rewrites `dev`'s own commits — avoid that.

## Starting work: create a worktree, then re-base it on `dev`

Use the built-in `EnterWorktree` tool to create the worktree — don't
hand-roll `git worktree add`. It's straightforward for the common case, but
its default base ref may not be `dev`: depending on the `worktree.baseRef`
setting, a fresh worktree branches from either `origin/<default-branch>`
(usually `main`) or your current local `HEAD`. Rather than trying to
predict which one applies, treat it as unknown and fix it up explicitly:

1. Call `EnterWorktree`.
2. Before making your first commit, run `git rebase dev` in the new
   worktree. If the branch already forked from `dev`'s tip, this is a
   no-op. If it forked from `main`/`origin` instead, this moves it onto
   `dev` — safe to do immediately since there are no commits of yours yet
   to conflict.
3. If there's no local `dev` branch at all, this repo hasn't adopted the
   worktree → dev → main split (or it hasn't been created yet). Creating
   the integration branch is a repo-setup decision for a human to make, not
   something to do unilaterally mid-task — say so rather than inventing one.

## Committing: atomic, buildable

Two things stay pure agent judgment (no script can make these calls for
you):

- **Atomic and at least buildable.** Each commit should be one coherent,
  self-contained change that leaves the project buildable — split unrelated
  changes into separate commits, and don't leave "WIP"/"tmp" states behind.
  Tests may fail at a given commit; the build must not.
- **A description that explains *why*, not just *what*** — the diff already
  shows what changed.

## Ephemeral specs: create, promote, inbox, drop

Spec-driven work often produces documents that matter *now* but shouldn't
live in the project forever. The clearest case today: once a code review
pass has validated its findings, write the review's artifacts under
`.spec/review/` — including a `.spec/review/TODO.md` tracking what the
review turned up. (This skill only reserves that location; the actual
shape and handling of `TODO.md` itself belongs to a separate, dedicated
TODO.md-handling skill.) Track `.spec/` in git, on the feature branch —
it's tracked, not gitignored, so the "why" behind a decision survives in
commit history for as long as the branch is alive.

Every spec file starts with YAML frontmatter containing a short, terse
`description:` (one to two sentences), from the moment it's created:

```markdown
---
description: Research on how to provision apt cache so that debian VMs can avoid doing apt update.
---
```

This means anything later moved into `.spec-inbox/` is already
compliant — there's no separate "add a description" step at inbox time.
It's what lets `scripts/list-spec-inbox.sh` (below) surface inbox entries
by description instead of just filenames.

`.spec/` never reaches `dev`: it exists only on feature branches and gets
removed in a final commit before landing. Three things can happen at that
point, two judgment calls and one mechanical step:

1. **Promote anything durable** (judgment call, not scriptable). Before
   dropping `.spec/`, look at what's in there and ask whether any of it
   should outlive the branch — e.g. a decision and its rationale that
   belongs in `docs/` (or wherever this project keeps permanent
   documentation). If so, make that a normal commit on the branch first.
   Most of what accumulates in `.spec/` won't clear this bar — that's
   expected, it's a workspace, not a destination.
2. **Inbox anything unconsumed** (judgment call, not scriptable). Some
   specs are neither durable-enough-for-docs/ nor safe to throw away —
   they just haven't been *consumed* yet (research done for this branch
   that turns out to matter for a different, not-yet-started feature is
   the common case). Move those into `.spec-inbox/` at the repo root,
   preserving their relative path under `.spec/` (e.g.
   `.spec/research/x.md` → `.spec-inbox/research/x.md`), via a normal
   `git mv` + commit. Unlike `.spec/`, `.spec-inbox/` is tracked on `dev`
   itself — not gitignored, not dropped before landing — because it's
   meant to outlive the branch that populated it; a later, unrelated
   branch is the expected consumer. Symmetrically, once a branch actually
   consumes an inbox entry (or determines it's gone stale), delete it from
   `.spec-inbox/` as a normal commit right then — this isn't limited to
   landing time, and like promotion, "is this still useful" is a judgment
   call, not something a script can decide. `land-to-dev.sh` lists inbox
   entries (path + description, via `scripts/list-spec-inbox.sh`) on every
   successful land, as a reminder to consider this — see below.
3. **Drop what's left of `.spec/`** (mechanical):
   ```sh
   ${CLAUDE_SKILL_DIR}/scripts/drop-specs.sh
   ```
   Run it from inside the worktree, on the branch being landed, after any
   promotion/inbox commits. It removes `.spec/` and commits the removal as
   `ai(cleanup): drop specs for <branch>` — the `ai` commit type is
   reserved for this: mechanically-generated commits from this skill's own
   scripts, never hand-written.

`land-to-dev.sh` (below) refuses to run if `.spec/` still differs from
`dev` on the branch being landed, so this can't be skipped by accident.
It never checks `.spec-inbox/` this way, since that directory is meant to
persist rather than be dropped.

`scripts/list-spec-inbox.sh` — run standalone any time, not just at
landing — prints one line per file under `.spec-inbox/`: the path and its
frontmatter `description:`, or `WARNING no description` if the file has
no frontmatter or no `description:` field (missing frontmatter shouldn't
block anything, just get flagged).
```sh
${CLAUDE_SKILL_DIR}/scripts/list-spec-inbox.sh
```

## Landing on `dev`

### User approval

First you must obtain an approve from the user. This is done because the user
may want to do additional stuff on the branch - conduct own review, make small fixes.

### Mechanics of landing

Once your worktree branch is done — buildable, commits atomic, any
`.spec/` content promoted-and-dropped (see above), **approved by the user**,
ready to be part of `dev`'s history — land it with:

```sh
${CLAUDE_SKILL_DIR}/scripts/land-to-dev.sh
```

Run it from inside the worktree, on the branch you're landing. It rebases
that branch onto `dev`'s current tip, then fast-forwards `dev` to match
(via `git fetch . <branch>:dev`, which only ever succeeds if it's a genuine
fast-forward — so if `dev` moved between your rebase and the landing, e.g.
another worktree landed first, it fails safely instead of overwriting
anything). It refuses to run from `main`, from `dev` itself, or from the
repo's main working directory, and refuses if there are uncommitted
changes.

If the rebase step hits conflicts, the script stops and tells you to
resolve them and rerun — conflict resolution is exactly the kind of
judgment call that shouldn't be scripted.

After a successful land, clean up the worktree (`ExitWorktree`, or
`git worktree remove` + `git branch -d` if it wasn't created via the tool).
If `dev` happens to be checked out in another worktree, that worktree's
`git status` will show it's now behind by however many commits it hasn't
refreshed — refresh it there when you next work in it; nothing is lost by
the fast-forward happening while it's checked out elsewhere.

## What this skill never does

- Commit, rebase, or fast-forward `main`. Promoting `dev` to `main` is a
  separate, deliberate human decision outside this workflow entirely.
- Force-push or force-update anything. Every ref update here is a genuine
  fast-forward; if that's not possible, the scripts fail rather than
  overwrite history.
- Create the `dev` branch itself. That's a one-time repo-setup step for a
  human, not something to infer and create on the fly.
