#!/usr/bin/env bash
# Bumps appVersion/version on every charts/*/Chart.yaml that opts in via the
# upstream annotation, when a newer stable tag exists within the same major.
# Edits the working tree only; prints the path of each changed Chart.yaml.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

ANNOTATION_KEY="0ekk.github.io/upstream-repo"

for chart_yaml in charts/*/Chart.yaml; do
  [[ -f "$chart_yaml" ]] || continue

  upstream_repo="$(yq ".annotations[\"${ANNOTATION_KEY}\"] // \"\"" "$chart_yaml")"
  [[ -n "$upstream_repo" ]] || continue

  current_app="$(yq '.appVersion' "$chart_yaml")"
  current_chart="$(yq '.version' "$chart_yaml")"
  current_major="${current_app%%.*}"

  latest_any="$(latest_stable_tag "$upstream_repo")"
  if [[ -n "$latest_any" ]]; then
    latest_any_major="${latest_any#v}"
    latest_any_major="${latest_any_major%%.*}"
    if [[ "$latest_any_major" != "$current_major" ]]; then
      echo "::warning::${chart_yaml}: newer major ${latest_any} available upstream (current ${current_app}); not auto-bumping across majors" >&2
    fi
  fi

  latest_in_major="$(latest_stable_tag "$upstream_repo" "$current_major")"
  [[ -n "$latest_in_major" ]] || continue

  new_app="${latest_in_major#v}"
  [[ "$new_app" != "$current_app" ]] || continue

  new_chart="$(next_chart_version "$current_chart" "$current_app" "$new_app")"

  yq -i ".appVersion = \"${new_app}\" | .version = \"${new_chart}\"" "$chart_yaml"
  echo "$chart_yaml"
done
