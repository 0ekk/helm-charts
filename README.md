# helm-charts

A personal Helm chart repository. `main` holds chart sources and provisioning
scripts; GitHub Actions validates, packages, and publishes them to `gh-pages`.

```sh
helm repo add 0ekk https://0ekk.github.io/helm-charts
helm repo update
```

## Charts

| Chart | Kind | Upstream |
|---|---|---|
| `code-server` | provisioned (chart packaged straight from upstream) | [coder/code-server](https://github.com/coder/code-server) |
| `distribution` | source (maintained in this repo) | [distribution/distribution](https://github.com/distribution/distribution) |

## How publishing works

`.github/workflows/release.yaml` runs on every push to `main`, on pull
requests (validation only), daily at 00:00 UTC, and on manual dispatch. Each
run: lints and validates every chart, packages source charts and runs
provisioning scripts, installs each into a `kind` cluster and runs `helm
test`, and — on `main` only — publishes the resulting `.tgz` files plus a
regenerated `index.yaml` to the `gh-pages` branch. There are no GitHub
Releases; `gh-pages` is the sole distribution artifact, and published
versions are immutable. A version is removed one year after it was
published, except each chart's newest version, which is always kept.

On the daily/manual runs, charts annotated with an upstream repo (see
`AGENTS.md`) are checked for a newer stable upstream release and bumped
automatically, committed to `main` via the GitHub API before validation and
publishing proceed.

See `AGENTS.md` for the repo layout and how to add a chart, and
`docs/plan/2026-09-18-helm-charts-repo.md` for the full design rationale.

## License

[Apache License 2.0](LICENSE). Applies to the chart sources and scripts in
this repo — each chart's own upstream software keeps its own license.
