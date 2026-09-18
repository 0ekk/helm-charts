#!/usr/bin/env bash
# Packages every chart under charts/*/ into <out-dir>/<name>/, then validates
# the packaged .tgz itself — not the source tree — with helm lint and helm
# template per ci/*-values.yaml (and defaults) piped through kubeconform.
# This applies the same way to source charts (helm package) and provisioned
# charts (provision.sh's own output), so a provisioned chart's packaged
# result gets the same scrutiny as one authored in this repo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib.sh

out_dir="${1:?usage: build.sh <out-dir>}"
mkdir -p "$out_dir"

KUBECONFORM_CRD_SCHEMA='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

render_and_check() {
  local name="$1" chart_dir="$2"
  shift 2
  helm template "$name" "$chart_dir" "$@" \
    | kubeconform -strict -summary \
        -schema-location default \
        -schema-location "$KUBECONFORM_CRD_SCHEMA"
}

# helm lint/template on this helm build only accept a chart directory, not a
# packaged archive, so unpack the .tgz we just produced/fetched and validate
# that extracted copy — it's byte-for-byte what gets published.
validate_package() {
  local name="$1" ci_dir="$2" tgz="$3"
  local extract_dir chart_dir
  extract_dir="$(mktemp -d)"
  tar xzf "$tgz" -C "$extract_dir"
  chart_dir="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"

  helm lint "$chart_dir"
  render_and_check "$name" "$chart_dir"

  shopt -s nullglob
  for values_file in "${ci_dir}"*-values.yaml; do
    render_and_check "$name" "$chart_dir" -f "$values_file"
  done
  shopt -u nullglob

  rm -rf "$extract_dir"
}

for chart_dir in charts/*/; do
  name="$(basename "$chart_dir")"
  has_chart_yaml=0
  has_provision=0
  [[ -f "${chart_dir}Chart.yaml" ]] && has_chart_yaml=1
  [[ -f "${chart_dir}provision.sh" ]] && has_provision=1

  if (( has_chart_yaml + has_provision != 1 )); then
    echo "charts/${name}: must have exactly one of Chart.yaml or provision.sh" >&2
    exit 1
  fi

  chart_out_dir="$out_dir/$name"
  mkdir -p "$chart_out_dir"

  if (( has_provision )); then
    echo "== provisioning ${name} =="
    bash "${chart_dir}provision.sh" "$chart_out_dir"
    if [[ -d "${chart_dir}overlay" || -d "${chart_dir}patches" || -d "${chart_dir}yq" ]]; then
      echo "== applying overlay to ${name} =="
      for tgz in "$chart_out_dir"/*.tgz; do
        apply_overlay "$chart_dir" "$tgz"
      done
    fi
  else
    echo "== packaging ${name} =="
    helm package "$chart_dir" -d "$chart_out_dir"
  fi

  echo "== validating ${name} =="
  shopt -s nullglob
  for tgz in "$chart_out_dir"/*.tgz; do
    validate_package "$name" "${chart_dir}ci/" "$tgz"
  done
  shopt -u nullglob
done
