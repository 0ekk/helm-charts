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

# expired_packages: 3.0.0 is old but newest (kept), 2.0.0 is recent (kept),
# 1.0.0 is old and its later move into demo/ must not count as a re-add.
pages="$tmp/pages"
mkdir -p "$pages/demo"
git init -q "$pages"
printf 'entries:\n  demo:\n' > "$pages/index.yaml"
for v in 3.0.0 2.0.0 1.0.0; do
  printf '    - urls: [https://x/demo/demo-%s.tgz]\n' "$v" >> "$pages/index.yaml"
done
# Throwaway fixture repo: fixed dates, isolated from the caller's git config.
fixture_commit() {
  git -C "$pages" add -A
  GIT_CONFIG_GLOBAL=/dev/null GIT_COMMITTER_DATE="@$1 +0000" GIT_AUTHOR_DATE="@$1 +0000" \
    git -C "$pages" -c user.name=test -c user.email=test@example.com commit -qm "at $1"
}
echo 1 > "$pages/demo-1.0.0.tgz"
echo 3 > "$pages/demo/demo-3.0.0.tgz"
fixture_commit 1600000000
echo 2 > "$pages/demo/demo-2.0.0.tgz"
fixture_commit 1700000000
git -C "$pages" mv demo-1.0.0.tgz demo/
fixture_commit 1750000000
assert_eq "demo-1.0.0.tgz" "$(expired_packages "$pages" 1650000000)" "expired_packages skips newest and recent, ignores moves"

echo "All tests passed."
