#!/usr/bin/env bash
# Validates and packages every chart under charts/*/ into <out-dir>.
# Source chart (has Chart.yaml): helm lint, helm template per ci/*-values.yaml
# (and defaults) piped through kubeconform, then helm package.
# Provisioned chart (has only provision.sh): delegates entirely to it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

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

  if (( has_provision )); then
    echo "== provisioning ${name} =="
    bash "${chart_dir}provision.sh" "$out_dir"
    continue
  fi

  echo "== building ${name} =="
  helm lint "$chart_dir"
  render_and_check "$name" "$chart_dir"

  shopt -s nullglob
  for values_file in "${chart_dir}"ci/*-values.yaml; do
    render_and_check "$name" "$chart_dir" -f "$values_file"
  done
  shopt -u nullglob

  helm package "$chart_dir" -d "$out_dir"
done
