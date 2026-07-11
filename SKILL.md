---
name: feature-branching
description: Enforces a worktree-per-branch git workflow with a `dev` integration branch sitting between feature work and `main` — creating worktrees off the right base, writing Conventional Commits, and landing finished work onto `dev` via rebase + fast-forward (never a merge commit, never touching `main`). Use this whenever the user asks to start work on something new, create or set up a worktree, land/merge/integrate a branch onto dev, check whether a commit message is formatted correctly, install a commit-msg hook, or asks whether a branch is "ready to merge" or "ready to land". Also trigger on "rebase my branch onto dev", "set up conventional commits for this repo", or any mention of a dev/main branch split — even if the user doesn't name this workflow directly.
---

# Feature branching: worktree → dev → main

This skill codifies one specific git topology: all agent work happens in a
throwaway worktree on its own branch; finished work lands on `dev` (the
shared integration branch) by rebase + fast-forward; `main` only moves
through a separate, deliberate promotion that this skill never performs.

The reasoning behind each rule matters more than the rule itself — read
"Why this shape" before mechanically applying the steps below.

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

**Naming the branch/worktree**: for ordinary feature work, `feature/<name>`
(see global `CLAUDE.md`'s "Branch naming" section for the full convention,
including the review-branch case). For a branch whose whole purpose is some
other goal — a review branch being the concrete example today — don't
hand-build the name — derive it from the goal and the branch or context
it's about:

```sh
scripts/normalize-branch-name.sh <goal> <source-branch>
```

This prints `<goal>/<source-branch-with-every-/-replaced-by-->`, e.g.
`review/feature-do_stuff` for a review (`<goal>` = `review`) of
`feature/do_stuff` — so the result is always exactly one slash deep no
matter how many segments the source branch's own name had. Pass that
string straight to `EnterWorktree` as `name`.

## Committing: Conventional Commits, atomic, buildable

Every commit title must follow
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[(scope)][!]: <description>
```

- `type` is one of `feat`, `fix`, `docs`, `refactor`, `test`, `chore` (adjust
  `hooks/commit-msg`'s allow-list if a project genuinely needs more, e.g.
  `perf`, `build`, `ci` — don't just add types because Conventional Commits
  permits them elsewhere).
- `scope` is optional, parenthesized, names the affected area:
  `fix(parser): ...`.
- `!` before the colon (or a `BREAKING CHANGE:` footer) marks a breaking
  change.

Install the validating hook **once per repo**, from any worktree — hooks
live in the repo's shared `.git/hooks`, not per-worktree, so this doesn't
need repeating for every new worktree:

```sh
/path/to/cc-skill-feature_branching/scripts/install-commit-msg-hook.sh
```

It symlinks `hooks/commit-msg` into place and makes it executable. If the
hook rejects a message, fix the wording rather than bypassing it with
`--no-verify` — a hook failure here means the message doesn't parse, not
that something is broken.

Beyond the title format, two things stay pure agent judgment (no script can
make these calls for you):

- **Atomic and at least buildable.** Each commit should be one coherent,
  self-contained change that leaves the project buildable — split unrelated
  changes into separate commits, and don't leave "WIP"/"tmp" states behind.
  Tests may fail at a given commit; the build must not.
- **A description that explains *why*, not just *what*** — the diff already
  shows what changed.

## Ephemeral specs: create, promote, drop

Spec-driven work often produces documents that matter *now* but shouldn't
live in the project forever. The clearest case today: once a code review
pass has validated its findings, write the review's artifacts under
`.specs/review/` — including a `.specs/review/TODO.md` tracking what the
review turned up. (This skill only reserves that location; the actual
shape and handling of `TODO.md` itself belongs to a separate, dedicated
TODO.md-handling skill.) Track `.specs/` in git, on the feature branch —
it's tracked, not gitignored, so the "why" behind a decision survives in
commit history for as long as the branch is alive.

`.specs/` never reaches `dev`: it exists only on feature branches and gets
removed in a final commit before landing. Two things happen at that point,
one judgment call and one mechanical step:

1. **Promote anything durable** (judgment call, not scriptable). Before
   dropping `.specs/`, look at what's in there and ask whether any of it
   should outlive the branch — e.g. a decision and its rationale that
   belongs in `docs/` (or wherever this project keeps permanent
   documentation). If so, make that a normal commit on the branch first.
   Most of what accumulates in `.specs/` won't clear this bar — that's
   expected, it's a workspace, not a destination.
2. **Drop what's left** (mechanical):
   ```sh
   /path/to/cc-skill-feature_branching/scripts/drop-specs.sh
   ```
   Run it from inside the worktree, on the branch being landed, after any
   promotion commit. It removes `.specs/` and commits the removal as
   `ai(cleanup): drop specs for <branch>` — the `ai` commit type is
   reserved for this: mechanically-generated commits from this skill's own
   scripts, never hand-written.

`land-to-dev.sh` (below) refuses to run if `.specs/` still differs from
`dev` on the branch being landed, so this can't be skipped by accident.

## Landing on `dev`

Once your worktree branch is done — buildable, commits atomic, any
`.specs/` content promoted-and-dropped (see above), ready to be part of
`dev`'s history — land it with:

```sh
/path/to/cc-skill-feature_branching/scripts/land-to-dev.sh
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
