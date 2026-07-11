#!/usr/bin/env bash
# Land the current worktree branch onto `dev`: rebase onto dev's current
# tip, then fast-forward dev to match. Never touches `main`. See SKILL.md
# for the reasoning behind each check below.
set -euo pipefail

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

if ! git diff --quiet dev...HEAD -- .specs 2>/dev/null; then
  echo "error: '$current_branch' has changes under .specs/ relative to dev." >&2
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

echo "Rebasing '$current_branch' onto tip of 'dev'..."
if ! git rebase dev; then
  echo >&2
  echo "error: rebase hit conflicts. Resolve them, run 'git rebase --continue', then rerun this script." >&2
  echo "(or 'git rebase --abort' to back out entirely)" >&2
  exit 1
fi

echo "Fast-forwarding 'dev' to '$current_branch' (fails if dev moved since the rebase)..."
if ! git fetch . "$current_branch:dev"; then
  echo >&2
  echo "error: could not fast-forward dev -- it likely moved since you rebased (e.g. another worktree landed first)." >&2
  echo "Rerun 'git rebase dev' to pick up the new tip, then rerun this script." >&2
  exit 1
fi

echo
echo "Landed. 'dev' now points at $(git rev-parse --short dev)."
echo "If dev is checked out in another worktree, it'll show as behind there until that worktree refreshes -- nothing is lost."
echo "Clean up this worktree/branch when you're done with it (ExitWorktree, or 'git worktree remove' + 'git branch -d $current_branch')."
