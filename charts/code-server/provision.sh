#!/usr/bin/env bash
# Provisioned chart: no local sources. Packages the Helm chart shipped inside
# the coder/code-server repo itself, at the latest stable upstream tag.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source scripts/lib.sh

out_dir="${1:?usage: provision.sh <out-dir>}"
mkdir -p "$out_dir"

upstream_repo="coder/code-server"
upstream_path="ci/helm-chart"

tag="$(latest_stable_tag "$upstream_repo")"
if [[ -z "$tag" ]]; then
  echo "no stable tag found for ${upstream_repo}" >&2
  exit 1
fi
version="${tag#v}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

git clone --quiet --filter=blob:none --no-checkout --depth 1 --branch "$tag" \
  "https://github.com/${upstream_repo}.git" "$tmp_dir/repo"
git -C "$tmp_dir/repo" sparse-checkout init --cone
git -C "$tmp_dir/repo" sparse-checkout set "$upstream_path"
git -C "$tmp_dir/repo" checkout --quiet "$tag"

chart_dir="$tmp_dir/repo/$upstream_path"
helm lint "$chart_dir"
helm package "$chart_dir" --version "$version" --app-version "$version" -d "$out_dir"
