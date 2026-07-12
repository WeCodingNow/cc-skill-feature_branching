#!/usr/bin/env bash
# List .spec-inbox/ entries with their frontmatter description, for the
# "did any of this go stale?" check. See SKILL.md's "Ephemeral specs"
# section for the frontmatter convention and .spec-inbox/'s lifecycle.
#
# Prints nothing if .spec-inbox/ doesn't exist or is empty. For each file,
# prints "<path>: <description>" if it has YAML frontmatter with a
# description: field, or "<path>: WARNING no description" otherwise --
# missing frontmatter shouldn't block anything, just get flagged.
set -euo pipefail

extract_description() {
  local file="$1"
  if [ "$(head -n1 "$file")" != "---" ]; then
    echo "WARNING no description"
    return
  fi
  local desc
  desc="$(awk 'NR==1{next} /^---$/{exit} {print}' "$file" \
    | sed -n 's/^description:[[:space:]]*//p' | head -n1)"
  # strip one layer of surrounding quotes, if present
  desc="${desc%\"}"; desc="${desc#\"}"
  desc="${desc%\'}"; desc="${desc#\'}"
  if [ -z "$desc" ]; then
    echo "WARNING no description"
  else
    echo "$desc"
  fi
}

if [ ! -d .spec-inbox ]; then
  exit 0
fi

find .spec-inbox -type f | sort | while IFS= read -r f; do
  echo "$f: $(extract_description "$f")"
done
