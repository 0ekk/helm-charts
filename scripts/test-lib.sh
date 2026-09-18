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

echo "All tests passed."
