#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

assert_eq() {
  local expected="$1" actual="$2" desc="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $desc (expected '$expected', got '$actual')" >&2
    exit 1
  fi
  echo "ok: $desc"
}

assert_eq "0.1.1" "$(next_chart_version 0.1.0 3.1.1 3.1.2)" "patch bump within same major.minor"
assert_eq "0.2.0" "$(next_chart_version 0.1.3 3.1.2 3.2.0)" "minor bump resets patch"
assert_eq "1.2.4" "$(next_chart_version 1.2.3 2.0.0 2.0.1)" "patch bump, multi-digit chart version"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/demo" "$tmp/out" "$tmp/src/overlay" "$tmp/src/patches" "$tmp/src/yq"
printf 'apiVersion: v2\nname: demo\nversion: 1.0.0\n' > "$tmp/demo/Chart.yaml"
printf 'a: 1\nb: 1\n' > "$tmp/demo/values.yaml"
helm package "$tmp/demo" -d "$tmp/out" >/dev/null
echo "added" > "$tmp/src/overlay/README.md"
printf -- '--- a/values.yaml\n+++ b/values.yaml\n@@ -1,2 +1,2 @@\n-a: 1\n+a: 2\n b: 1\n' \
  > "$tmp/src/patches/0001-a.patch"
echo '.b = 3' > "$tmp/src/yq/values.yaml.yq"
apply_overlay "$tmp/src/" "$tmp/out/demo-1.0.0.tgz"
assert_eq $'a: 2\nb: 3' "$(tar xzOf "$tmp/out/demo-1.0.0.tgz" demo/values.yaml)" "apply_overlay applies patches, then yq"
assert_eq "added" "$(tar xzOf "$tmp/out/demo-1.0.0.tgz" demo/README.md)" "apply_overlay copies overlay files"
# Same patch again no longer applies (a is already 2): must fail, not skip.
# Separate process: set -e is ignored inside an `if` condition's subshell.
if bash -euo pipefail -c 'source lib.sh; apply_overlay "$@"' _ \
    "$tmp/src/" "$tmp/out/demo-1.0.0.tgz" 2>/dev/null; then
  echo "FAIL: apply_overlay accepted a patch that does not apply" >&2
  exit 1
fi
echo "ok: apply_overlay fails on a stale patch"

echo "All tests passed."
