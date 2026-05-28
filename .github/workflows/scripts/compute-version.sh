#!/usr/bin/env bash
# Usage: scripts/compute-version.sh <patch|minor|major>
# Reads ./VERSION, computes next semver, prints to stdout.
set -euo pipefail

BUMP="${1:-}"
if [ -z "$BUMP" ]; then
  echo "Usage: $0 <patch|minor|major>" >&2
  exit 2
fi

if [ ! -f VERSION ]; then
  echo "VERSION file not found (run from repo root)" >&2
  exit 1
fi

CURRENT=$(tr -d '[:space:]' < VERSION)
if ! echo "$CURRENT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Invalid current VERSION: $CURRENT" >&2
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP" in
  major) NEW="$((MAJOR + 1)).0.0" ;;
  minor) NEW="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) NEW="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  *) echo "Unknown bump type: $BUMP (expected patch|minor|major)" >&2; exit 2 ;;
esac

echo "$NEW"
