#!/usr/bin/env bash
# Shared helpers for scripts/*.sh and charts/*/provision.sh. Sourced, not executed.

latest_stable_tag() {
  local repo="$1" major="${2:-}"
  local filter='^v[0-9]+\.[0-9]+\.[0-9]+$'
  if [[ -n "$major" ]]; then
    filter="^v${major}\.[0-9]+\.[0-9]+\$"
  fi
  git ls-remote --tags --refs --sort=-v:refname "https://github.com/${repo}.git" 'refs/tags/v*' \
    | sed 's#.*refs/tags/##' \
    | grep -E "$filter" \
    | head -n1
}

next_chart_version() {
  local chart_ver="$1" old_app="$2" new_app="$3"
  local old_mm="${old_app%.*}" new_mm="${new_app%.*}"
  local major minor patch
  IFS=. read -r major minor patch <<<"$chart_ver"
  if [[ "$old_mm" == "$new_mm" ]]; then
    echo "${major}.${minor}.$((patch + 1))"
  else
    echo "${major}.$((minor + 1)).0"
  fi
}
