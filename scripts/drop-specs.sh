#!/usr/bin/env bash
# Drop this branch's ephemeral .spec/ before landing: removes .spec/ in one
# commit so it never reaches `dev`. Run only after anything durable has
# already been promoted elsewhere (e.g. into docs/) as its own commit -- see
# SKILL.md's "Ephemeral specs" section for that judgment call.
set -euo pipefail

current_branch=$(git branch --show-current)
if [ -z "$current_branch" ]; then
  echo "error: not on a branch (detached HEAD) -- nothing to drop" >&2
  exit 1
fi

if [ "$current_branch" = "main" ] || [ "$current_branch" = "dev" ]; then
  echo "error: refusing to touch .spec/ on '$current_branch' -- check out your worktree's own feature branch first" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet dev >/dev/null; then
  echo "error: no local 'dev' branch found -- this repo may not use the worktree -> dev -> main workflow" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: uncommitted changes present -- commit them (including any docs/ promotion) before dropping .spec/" >&2
  exit 1
fi

if [ ! -d .spec ]; then
  echo "No .spec/ directory on '$current_branch' -- nothing to drop."
  exit 0
fi

git rm -r --quiet .spec
git commit --quiet -m "ai(cleanup): drop specs for $current_branch"

echo "Dropped .spec/ in a new commit on '$current_branch' ($(git rev-parse --short HEAD))."
