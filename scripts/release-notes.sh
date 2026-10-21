#!/usr/bin/env bash
# Prints Markdown release notes for VERSION: a short description plus the
# commits since the previous vX.Y.Z tag, grouped by Conventional Commit type.
#
# Usage: scripts/release-notes.sh VERSION [OWNER/REPO]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 VERSION [OWNER/REPO]" >&2
  exit 1
fi

version="${1#v}"
repo="${2:-${GITHUB_REPOSITORY:-antonioaren/Hyperactive}}"
repo_url="https://github.com/$repo"

previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
if [[ "$previous_tag" == "v$version" ]]; then
  previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "v$version^" 2>/dev/null || true)"
fi

if [[ -n "$previous_tag" ]]; then
  range="$previous_tag..HEAD"
else
  range="HEAD"
fi

features=()
fixes=()
breaking=()
others=()

type_re='^([a-zA-Z]+)(\(([^)]*)\))?(!)?:[[:space:]]*(.*)$'

while IFS=$'\x1f' read -r hash subject author; do
  [[ -z "$hash" ]] && continue
  type=""
  text="$subject"
  bang=""
  if [[ "$subject" =~ $type_re ]]; then
    type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    text="${BASH_REMATCH[5]}"
    if [[ -n "$scope" ]]; then
      text="**$scope:** $text"
    fi
  fi
  entry="- $text ([\`$hash\`]($repo_url/commit/$hash)) by $author"

  if [[ -n "$bang" ]] || git log -1 --format='%B' "$hash" | grep -qE '^BREAKING[ -]CHANGE:'; then
    breaking+=("$entry")
  elif [[ "$type" == "feat" ]]; then
    features+=("$entry")
  elif [[ "$type" == "fix" ]]; then
    fixes+=("$entry")
  else
    others+=("$entry")
  fi
done < <(git log --no-merges --format='%h%x1f%s%x1f%an' "$range")

total=$(( ${#breaking[@]} + ${#features[@]} + ${#fixes[@]} + ${#others[@]} ))

plural() {
  if [[ "$1" -eq 1 ]]; then echo "$1 $2"; else echo "$1 ${3:-$2s}"; fi
}

summary_parts=()
[[ ${#breaking[@]} -gt 0 ]] && summary_parts+=("$(plural ${#breaking[@]} "breaking change")")
[[ ${#features[@]} -gt 0 ]] && summary_parts+=("$(plural ${#features[@]} "new feature")")
[[ ${#fixes[@]} -gt 0 ]] && summary_parts+=("$(plural ${#fixes[@]} "bug fix" "bug fixes")")
[[ ${#others[@]} -gt 0 ]] && summary_parts+=("$(plural ${#others[@]} "other change")")

if [[ ${#others[@]} -eq "$total" ]]; then
  summary_parts=()
fi

summary=""
for i in "${!summary_parts[@]}"; do
  if [[ $i -eq 0 ]]; then
    summary="${summary_parts[$i]}"
  elif [[ $i -eq $(( ${#summary_parts[@]} - 1 )) ]]; then
    summary="$summary and ${summary_parts[$i]}"
  else
    summary="$summary, ${summary_parts[$i]}"
  fi
done

print_section() {
  local title="$1"
  shift
  [[ $# -eq 0 ]] && return
  printf '### %s\n\n' "$title"
  printf '%s\n' "$@"
  printf '\n'
}

{
  printf '## Hyperactive v%s\n\n' "$version"

  if [[ -n "$previous_tag" ]]; then
    printf 'This release contains %s since %s' "$(plural "$total" commit)" "$previous_tag"
  else
    printf 'First versioned release of Hyperactive, a macOS menu bar app that keeps your Mac awake. It contains %s' "$(plural "$total" commit)"
  fi
  if [[ -n "$summary" ]]; then
    printf ': %s.\n\n' "$summary"
  else
    printf '.\n\n'
  fi

  print_section "Breaking changes" ${breaking[@]+"${breaking[@]}"}
  print_section "New features" ${features[@]+"${features[@]}"}
  print_section "Bug fixes" ${fixes[@]+"${fixes[@]}"}
  print_section "Other changes" ${others[@]+"${others[@]}"}

  cat <<EOF
### Downloads

| File | Description |
| --- | --- |
| \`Hyperactive-$version.dmg\` | Disk image. Open it and drag Hyperactive to Applications. |
| \`Hyperactive-$version-macOS.zip\` | Zipped app (Apple silicon + Intel). Used by the in-app updater. |
| \`Hyperactive-$version-source.zip\` | Source code at this release. |

### Install or update

- **New install:** open the DMG and drag \`Hyperactive.app\` to \`/Applications\`. If macOS shows a Gatekeeper warning, right-click the app and choose **Open**.
- **Already installed:** open the Hyperactive menu and click **Update to v$version**.
- After updating, macOS may ask you to grant Accessibility access again (System Settings > Privacy & Security > Accessibility).

Requires macOS 14 (Sonoma) or later.
EOF

  if [[ -n "$previous_tag" ]]; then
    printf '\n**Full changelog:** %s/compare/%s...v%s\n' "$repo_url" "$previous_tag" "$version"
  fi
}
