#!/usr/bin/env bash
# Prints the next semantic version (without the leading "v") based on the
# Conventional Commits since the latest vX.Y.Z tag reachable from HEAD.
#
#   BREAKING CHANGE / type!:  -> major
#   feat:                     -> minor
#   anything else             -> patch
#
# Prints nothing when there is nothing to release: HEAD is already tagged, or
# the HEAD commit message contains "[skip release]".
set -euo pipefail

INITIAL_VERSION="${INITIAL_VERSION:-1.0.0}"

if git log -1 --format='%B' HEAD | grep -qiF '[skip release]'; then
  exit 0
fi

last_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"

if [[ -z "$last_tag" ]]; then
  echo "$INITIAL_VERSION"
  exit 0
fi

if [[ ! "${last_tag#v}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Latest tag '$last_tag' is not a vMAJOR.MINOR.PATCH version" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

if [[ -z "$(git rev-list "$last_tag..HEAD")" ]]; then
  exit 0
fi

breaking_re='^[a-zA-Z]+(\([^)]*\))?!:'
feature_re='^feat(\([^)]*\))?:'

bump="patch"
while IFS= read -r -d $'\x1e' message; do
  subject="$(printf '%s\n' "$message" | sed -e '/./,$!d' | head -n 1)"
  if [[ "$subject" =~ $breaking_re ]] || printf '%s\n' "$message" | grep -qE '^BREAKING[ -]CHANGE:'; then
    bump="major"
    break
  fi
  if [[ "$subject" =~ $feature_re ]]; then
    bump="minor"
  fi
done < <(git log --format='%B%x1e' "$last_tag..HEAD")

case "$bump" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "$major.$((minor + 1)).0" ;;
  patch) echo "$major.$minor.$((patch + 1))" ;;
esac
