#!/usr/bin/env bash
# Land the current worktree branch onto `dev`: rebase onto dev's current
# tip, then fast-forward dev to match. Never touches `main`. See SKILL.md
# for the reasoning behind each check below.
set -euo pipefail

# Resolves to this script's own directory, so the sibling script below can
# be called by an absolute path -- this script is documented to run with
# the worktree root as cwd (see SKILL.md), not from inside scripts/, so a
# bare `list-spec-inbox.sh` call would fail (not on PATH, not in cwd).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

current_branch=$(git branch --show-current)
if [ -z "$current_branch" ]; then
  echo "error: not on a branch (detached HEAD) -- nothing to land" >&2
  exit 1
fi

if [ "$current_branch" = "main" ] || [ "$current_branch" = "dev" ]; then
  echo "error: refusing to land from '$current_branch' -- check out your worktree's own feature branch first" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet dev >/dev/null; then
  echo "error: no local 'dev' branch found -- this repo may not use the worktree -> dev -> main workflow" >&2
  exit 1
fi

if ! git diff --quiet dev...HEAD -- .spec 2>/dev/null; then
  echo "error: '$current_branch' has changes under .spec/ relative to dev." >&2
  echo "Promote anything durable (e.g. into docs/) as its own commit, then run scripts/drop-specs.sh, then rerun this script." >&2
  exit 1
fi

main_worktree=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
if [ "$(pwd -P)" = "$(cd "$main_worktree" && pwd -P)" ]; then
  echo "error: refusing to land from the repo's main working directory -- do this from the feature branch's own worktree" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: uncommitted changes present -- commit or stash before landing" >&2
  exit 1
fi

# A submodule commit this branch introduces can exist only in this worktree's
# submodule checkout -- removing the worktree then destroys it, and the gitlink
# referencing it dangles for anyone who fetches. Refuse to land such a commit
# until it's on the submodule's origin. Only gitlinks this branch *moves*
# relative to dev are at risk; an unchanged gitlink was vetted when it landed.
if [ -f .gitmodules ]; then
  sub_paths=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
  for sub in $sub_paths; do
    new=$(git rev-parse --verify --quiet "HEAD:$sub") || continue   # not a gitlink
    old=$(git rev-parse --verify --quiet "dev:$sub" 2>/dev/null || printf '')
    [ "$new" = "$old" ] && continue                                 # gitlink unchanged
    # Verify only when the submodule is checked out here -- the only way its new
    # commit could live in this worktree and vanish with it. Guard on the `.git`
    # entry: `git -C` on an uninitialised submodule dir walks up to the
    # superproject and would check the wrong repo.
    [ -e "$sub/.git" ] || continue
    git -C "$sub" fetch --quiet origin 2>/dev/null || true
    if [ -z "$(git -C "$sub" branch -r --contains "$new" 2>/dev/null)" ]; then
      echo "error: submodule '$sub' records commit ${new:0:12}, which is not on its origin." >&2
      echo "Removing this worktree would destroy that commit. Land the submodule's 'dev' onto its" >&2
      echo "'main' and push it (agents don't push -- ask the user), then rerun this script." >&2
      exit 1
    fi
  done
fi

echo "Rebasing '$current_branch' onto tip of 'dev'..."
if ! git rebase dev; then
  echo >&2
  echo "error: rebase hit conflicts. Resolve them, run 'git rebase --continue', then rerun this script." >&2
  echo "(or 'git rebase --abort' to back out entirely)" >&2
  exit 1
fi

echo "Fast-forwarding 'dev' to '$current_branch' (fails if dev moved since the rebase)..."
# --update-head-ok: dev may be checked out (as HEAD) in the repo's main
# working directory or another worktree. git fetch refuses to update such a
# ref by default as a safety check unrelated to fast-forward-ness; this
# flag lifts that check. The actual safety property we rely on -- that this
# only ever succeeds as a genuine fast-forward -- is unaffected: git fetch
# still fails the ref update if dev is not an ancestor of $current_branch.
# Any worktree with dev checked out simply won't see the new commits in its
# working files/index until it's refreshed there (see message below).
if ! git fetch . --update-head-ok "$current_branch:dev"; then
  echo >&2
  echo "error: could not fast-forward dev -- it likely moved since you rebased (e.g. another worktree landed first)." >&2
  echo "Rerun 'git rebase dev' to pick up the new tip, then rerun this script." >&2
  exit 1
fi

echo
echo "Landed. 'dev' now points at $(git rev-parse --short dev)."
echo "If dev is checked out in another worktree, it'll show as behind there until that worktree refreshes -- nothing is lost."
echo "Clean up this worktree/branch when you're done with it (ExitWorktree, or 'git worktree remove' + 'git branch -d $current_branch')."

if [ -d .spec-inbox ] && [ -n "$(find .spec-inbox -type f -print -quit)" ]; then
  echo
  echo "Did something in this list go stale?"
  "$SCRIPT_DIR/list-spec-inbox.sh"
fi
