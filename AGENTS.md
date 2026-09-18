# AGENTS.md

Personal multi-chart Helm repository. `main` holds chart sources and
provisioning scripts; one GitHub Actions workflow (`.github/workflows/release.yaml`)
validates, packages and publishes them to the `gh-pages` branch. There are no
GitHub Releases — `gh-pages`' `index.yaml` + the packaged `.tgz` files are the
only distribution artifact. See `docs/plan/2026-09-18-helm-charts-repo.md`
for the full design rationale.

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
