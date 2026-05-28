#!/usr/bin/env bash
# Usage: scripts/apply-version.sh <new-version>
# Writes <new-version> to VERSION, both plugin.json files, and build.sh
# (CFBundleShortVersionString + increments CFBundleVersion integer).
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
         plugin/.codex-plugin/plugin.json \
         token-usage-app/build.sh; do
  if [ ! -f "$f" ]; then
    echo "Missing file: $f (run from repo root)" >&2
    exit 1
  fi
done

# VERSION
echo "$NEW" > VERSION

# plugin.json × 2
for manifest in plugin/.claude-plugin/plugin.json plugin/.codex-plugin/plugin.json; do
  jq --arg v "$NEW" '.version = $v' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"
done

# build.sh — CFBundleShortVersionString → NEW; CFBundleVersion → +1
FILE=token-usage-app/build.sh
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(sed -i -E)
else
  SED_INPLACE=(sed -i '' -E)
fi

"${SED_INPLACE[@]}" "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]+</string>|<string>${NEW}</string>|;}" "$FILE"

CURRENT_BUILD=$(sed -n -E '/<key>CFBundleVersion<\/key>/{n;s|.*<string>([0-9]+)</string>.*|\1|p;}' "$FILE")
if [ -z "$CURRENT_BUILD" ]; then
  echo "Could not parse CFBundleVersion from $FILE" >&2
  exit 1
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
"${SED_INPLACE[@]}" "/<key>CFBundleVersion<\/key>/{n;s|<string>[0-9]+</string>|<string>${NEW_BUILD}</string>|;}" "$FILE"

echo "Updated to $NEW (CFBundleVersion=$NEW_BUILD)"
