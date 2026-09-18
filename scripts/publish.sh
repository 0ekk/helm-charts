#!/usr/bin/env bash
# Publishes every <dist-dir>/<component>/*.tgz to the gh-pages branch, one
# directory per component: copies new packages (existing ones are immutable
# and skipped), rebuilds index.yaml from the tgz set (source of truth, so a
# repo rename needs no migration step), regenerates gh-pages/README.md,
# commits and pushes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

dist_dir="${1:?usage: publish.sh <dist-dir>}"
repo_name="$(basename -s .git "$(git remote get-url origin)")"
chart_repo_url="${CHART_REPO_URL:-https://${GITHUB_REPOSITORY_OWNER:-0ekk}.github.io/${repo_name}}"

worktree_dir="$(mktemp -d)"
rmdir "$worktree_dir"
cleanup() { git worktree remove --force "$worktree_dir" 2>/dev/null || true; }
trap cleanup EXIT

if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch origin gh-pages:gh-pages
  git worktree add "$worktree_dir" gh-pages
else
  git worktree add --detach "$worktree_dir"
  git -C "$worktree_dir" switch --orphan gh-pages
  git -C "$worktree_dir" rm -rf . >/dev/null 2>&1 || true
fi

# -c instead of `git config`: a worktree shares its parent repo's config
# file by default, so a persistent `git config` here would silently
# overwrite the caller's own identity when this script is run locally
# (see docs/plan/2026-09-18-helm-charts-repo.md).
git_bot() {
  git -C "$worktree_dir" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    "$@"
}

added=0
shopt -s nullglob
for tgz in "$dist_dir"/*/*.tgz; do
  component="$(basename "$(dirname "$tgz")")"
  base="$(basename "$tgz")"
  dest_dir="$worktree_dir/$component"
  if [[ -f "$dest_dir/$base" ]]; then
    echo "::notice::${component}/${base} already published, skipping"
    continue
  fi
  mkdir -p "$dest_dir"
  cp "$tgz" "$dest_dir/$base"
  added=1
done
shopt -u nullglob

index_is_current() {
  local idx="$1"
  [[ -f "$idx" ]] || return 1
  ! yq '.entries[][].urls[]' "$idx" | grep -qv "^${chart_repo_url}/"
}

if (( ! added )) && index_is_current "$worktree_dir/index.yaml"; then
  echo "nothing new to publish; index already up to date"
  exit 0
fi

helm repo index "$worktree_dir" --url "$chart_repo_url"

{
  echo "# Helm charts"
  echo
  echo "This branch is managed by GitHub Actions. Do not edit by hand."
  echo
  echo '```sh'
  echo "helm repo add 0ekk ${chart_repo_url}"
  echo "helm repo update"
  echo '```'
  echo
  echo "## Charts"
  echo
  echo "| Chart | Versions published |"
  echo "|---|---|"
  yq '.entries | keys | .[]' "$worktree_dir/index.yaml" | while read -r name; do
    count="$(yq ".entries[\"${name}\"] | length" "$worktree_dir/index.yaml")"
    echo "| ${name} | ${count} |"
  done
} > "$worktree_dir/README.md"

git -C "$worktree_dir" add -A
if git -C "$worktree_dir" diff --cached --quiet; then
  echo "no gh-pages changes to publish"
  exit 0
fi
git_bot commit -m "Publish charts"
git -C "$worktree_dir" push origin HEAD:gh-pages
