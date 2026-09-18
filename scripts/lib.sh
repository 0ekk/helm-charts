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

# apply_overlay <chart-src-dir/> <tgz>: for provisioned charts. Copies
# <chart-src-dir>/overlay/ over the packaged chart (whole files, added or
# replaced), then applies <chart-src-dir>/patches/*.patch in lexical order
# (git-style diffs, paths relative to the chart root), then runs each
# <chart-src-dir>/yq/<path>.yq as a yq expression editing <path> in place,
# and repackages <tgz>. A patch that no longer applies to a newer upstream
# fails; yq runs last so its reformatting can't break a patch's context.
apply_overlay() {
  local src_dir="$1" tgz="$2"
  local work_dir chart_dir patch_file expr_file target
  work_dir="$(mktemp -d)"
  tar xzmf "$tgz" -C "$work_dir"
  chart_dir="$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"

  if [[ -d "${src_dir}overlay" ]]; then
    cp -R "${src_dir}overlay/." "$chart_dir/"
  fi
  shopt -s nullglob
  for patch_file in "${src_dir}"patches/*.patch; do
    git -C "$chart_dir" apply < "$patch_file"
  done
  shopt -u nullglob
  if [[ -d "${src_dir}yq" ]]; then
    while IFS= read -r expr_file; do
      target="${expr_file#"${src_dir}yq/"}"
      yq -i --from-file "$expr_file" "$chart_dir/${target%.yq}"
    done < <(find "${src_dir}yq" -type f -name '*.yq' | sort)
  fi

  rm "$tgz"
  helm package "$chart_dir" -d "$(dirname "$tgz")" >/dev/null
  rm -rf "$work_dir"
}
