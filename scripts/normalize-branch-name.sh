#!/usr/bin/env bash
# Print <goal>/<source-branch, with every / replaced by ->. "goal" is a
# free-form label for why the branch exists -- there's no fixed list, e.g.
# "review" for a review branch. See global CLAUDE.md's "Branch naming"
# section.
set -euo pipefail

goal="${1:-}"
source_branch="${2:-}"
if [ -z "$goal" ] || [ -z "$source_branch" ]; then
  echo "usage: $(basename "$0") <goal> <source-branch-name>" >&2
  echo "  e.g.: $(basename "$0") review feature/do_stuff  ->  review/feature-do_stuff" >&2
  exit 1
fi

echo "$goal/$(tr '/' '-' <<<"$source_branch")"
