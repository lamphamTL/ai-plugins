#!/usr/bin/env bash
# Usage: apply-version.sh <new-version>
# Writes <new-version> to VERSION and both plugin.json files.
set -euo pipefail

NEW="${1:-}"
if [ -z "$NEW" ]; then
  echo "Usage: $0 <new-version>" >&2
  exit 2
fi
if ! echo "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Invalid version: $NEW (expected X.Y.Z)" >&2
  exit 1
fi

for f in VERSION \
         plugin/.claude-plugin/plugin.json \
         plugin/.codex-plugin/plugin.json; do
  if [ ! -f "$f" ]; then
    echo "Missing file: $f (run from repo root)" >&2
    exit 1
  fi
done

# Update VERSION
echo "$NEW" > VERSION

# Update claude and codex plugin.json
for manifest in plugin/.claude-plugin/plugin.json plugin/.codex-plugin/plugin.json; do
  jq --arg v "$NEW" '.version = $v' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"
done

echo "Updated to $NEW"
