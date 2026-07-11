#!/usr/bin/env bash
# Install the commit-msg hook into the current repo's shared .git/hooks --
# safe to run from any worktree since hooks aren't per-worktree (they live
# in the common git dir). Idempotent: safe to rerun.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git_common_dir="$(git rev-parse --git-common-dir)"
hook_dest="${git_common_dir}/hooks/commit-msg"

if [ -e "$hook_dest" ] && [ ! -L "$hook_dest" ]; then
  echo "error: $hook_dest already exists and isn't a symlink -- back it up or merge it by hand" >&2
  exit 1
fi

mkdir -p "${git_common_dir}/hooks"
ln -sf "$skill_dir/hooks/commit-msg" "$hook_dest"
chmod +x "$skill_dir/hooks/commit-msg"

echo "Installed commit-msg hook -> $hook_dest (shared across all worktrees of this repo)"
