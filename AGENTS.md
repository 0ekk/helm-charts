# AGENTS.md

Personal multi-chart Helm repository. `main` holds chart sources and
provisioning scripts; one GitHub Actions workflow (`.github/workflows/release.yaml`)
validates, packages and publishes them to the `gh-pages` branch. There are no
GitHub Releases — `gh-pages`' `index.yaml` + the packaged `.tgz` files are the
only distribution artifact. See `docs/plan/2026-09-18-helm-charts-repo.md`
for the full design rationale.

Retention: `scripts/publish.sh` deletes every package first published to
`gh-pages` more than a year ago (date = the last git commit that added the
`.tgz`; a move doesn't count), except each chart's newest version.

## Layout

```
charts/<name>/
```

Each chart directory is exactly one of:

- **Source chart**: has `Chart.yaml` (a real Helm chart living in this repo).
- **Provisioned chart**: has only `provision.sh`, an executable script
  `provision.sh <out-dir>` that fetches/packages a chart from elsewhere
  (e.g. `charts/code-server/provision.sh` packages the chart shipped inside
  `coder/code-server` itself) and drops the resulting `.tgz` into `<out-dir>`.

`scripts/build.sh` fails the build if a chart directory has both or neither.

## Adding a chart

Source chart:

1. `charts/<name>/Chart.yaml`, `values.yaml`, `templates/`.
2. `charts/<name>/ci/*-values.yaml` — one file per scenario the workflow
   installs into a kind cluster and runs `helm test` against.
3. A `templates/tests/*.yaml` Helm test hook so `helm test` has something to run.
4. **Bump the chart `version` on every change to a source chart** — published
   versions on `gh-pages` are immutable; `scripts/publish.sh` never overwrites
   an existing `.tgz`, so re-publishing under the same version does nothing.
5. To opt into automated upstream-version bumps, add the annotation
   `0ekk.github.io/upstream-repo: <owner/repo>` to `Chart.yaml`. `scripts/bump.sh`
   then tracks that repo's newest stable tag (`vMAJOR.MINOR.PATCH`, no
   pre-releases) within the chart's current major version, bumping
   `appVersion` to match and `version` by the same granularity (patch bump
   upstream → patch bump chart; minor → minor). A newer upstream major only
   emits a `::warning::`; it is never bumped automatically.

Provisioned chart: just `charts/<name>/provision.sh`, executable, taking one
argument (the output directory) and producing one packaged `.tgz` there.

### Overlay on a provisioned chart

`scripts/build.sh` modifies the packaged upstream chart before validating it
(`apply_overlay` in `scripts/lib.sh`), in this order:

1. `charts/<name>/overlay/` — copied over the chart root, whole files added or
   replaced (e.g. `overlay/templates/extra.yaml`).
2. `charts/<name>/patches/*.patch` — `git apply`'d in lexical order, paths
   relative to the chart root. For text edits yq can't express (templates).
3. `charts/<name>/yq/<path>.yq` — a yq expression run in place on `<path>`
   (e.g. `yq/values.yaml.yq` edits `values.yaml`). Preferred for YAML
   (`values.yaml`, `Chart.yaml`): it survives upstream reformatting that
   breaks a patch. Never copy a whole `values.yaml` into `overlay/` — it
   would freeze everything upstream changes later (code-server's pins
   `image.tag`).

A patch that no longer applies to a newer upstream fails the whole build —
fix or drop it. Author a patch against the pristine chart:

```sh
charts/<name>/provision.sh /tmp/p && tar xzf /tmp/p/*.tgz -C /tmp/p
cd /tmp/p/<name> && git init -q && git add -A     # staged = pristine base
# edit files (`git add -N` any new file), then:
mkdir -p "$OLDPWD/charts/<name>/patches"
git diff > "$OLDPWD/charts/<name>/patches/0001-<topic>.patch"
```

A yq expression never fails on its own: if upstream renames a key, `=`
silently creates a dead one. Guard keys you set on purpose, chaining
statements with `|` (`#` comments are allowed):

```
# charts/code-server/yq/values.yaml.yq
.replicaCount = 2 |
with(.image; has("pullPolicy") or error("image.pullPolicy gone upstream")) |
.image.pullPolicy = "IfNotPresent"
```

yq keeps every value and comment, but rewrites the file's layout: blank
lines are dropped and comments inside maps are un-indented.

The chart version stays equal to the upstream version, and published
versions are immutable, so an overlay change is validated right away but
only ships with the next upstream release.

## Local commands

```sh
scripts/test-lib.sh                 # unit tests for scripts/lib.sh
scripts/build.sh dist               # lint + kubeconform + package every chart into dist/
scripts/bump.sh                     # check upstream versions, edit Chart.yaml in place
CHART_REPO_URL=... scripts/publish.sh dist   # publish dist/*.tgz to gh-pages (mutates git)
shellcheck scripts/*.sh charts/*/provision.sh
```

`scripts/build.sh` needs `helm`, `kubeconform`, and `yq` on PATH.
`charts/code-server/provision.sh` needs network access to `github.com`.

## Git

All commits must be GPG-signed (`git commit -S`). The one exception is
`scripts/publish.sh` and the workflow's version-bump step, which write to
`gh-pages` with a plain push and commit to `main` via the GitHub Contents API
respectively — both come out as `github-actions[bot]`, verified by GitHub
without a local GPG key.
