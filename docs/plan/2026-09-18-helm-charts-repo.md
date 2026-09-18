# helm-charts: personal multi-chart repo (plan)

Status: implemented on `main`, locally verified. Decided 2026-09-18, implemented 2026-09-18.
Not yet rolled out: GitHub repo rename, first push to the new remote, and
deletion of the 17 old `v4.x` releases (rollout steps 2–5) — these need the
repo owner's go-ahead since they're hard to reverse.

## Context

`0ekk/code-server-chart` today has one workflow (`.github/workflows/sync-code-server-chart.yml`)
that daily fetches the latest stable `coder/code-server` tag, packages `ci/helm-chart` with
version = appVersion = upstream version, copies the tgz onto `gh-pages`, merges `index.yaml`,
and creates a GitHub Release `v<version>`. gh-pages holds 17 code-server tgz
(4.122.0 … 4.137.0) indexed under `https://0ekk.github.io/code-server-chart`.

Goal: rename to `helm-charts` and turn it into a multi-chart personal repo. `main` holds chart
sources or provisioning scripts; one GitHub Actions workflow validates, packages and publishes
to `gh-pages`. This change: wrap code-server as a provisioning script, author a new chart for
`distribution/distribution` (registry v3), with automated upstream bumps.

## Decisions (confirmed by repo owner)

| # | Decision |
|---|----------|
| D1 | Keep the 17 old code-server tgz; reindex all under `https://0ekk.github.io/helm-charts`. Old Pages URL breaks (GitHub does not redirect Pages on rename). |
| D2 | Unified `charts/<name>/`: source chart = has `Chart.yaml`; provisioned chart = has only `provision.sh`. Exactly one of the two, else build fails. |
| D3 | tgz + `index.yaml` live on `gh-pages`. No GitHub Releases. |
| D4/D5 | Registry supports private (default) and pull-through proxy; one release = one instance. |
| D6 | `config:` dict passthrough, deep-merged over chart defaults, rendered to a Secret; secrets via `extraEnv` (`REGISTRY_*`). |
| D7 | v0.1.0 extras: Ingress, metrics (+ optional ServiceMonitor), htpasswd helper (existing Secret), GC. |
| D8 | CI: helm lint + kubeconform + kind install per `ci/*-values.yaml` + `helm test`. PRs validate only. |
| D9 | GC = initContainer `registry garbage-collect` before registry starts (Recreate ⇒ no writer); CronJob `registry.k8s.io/kubectl` runs `rollout restart`. GC enabled ⇒ replicaCount must be 1. GC failure logs, never blocks startup. |
| D10 | Chart name `distribution`. |
| D11/D13 | Scheduled auto-bump within the same upstream major; chart bump level follows upstream (patch→patch, minor→minor); newer major ⇒ `::warning::` only. |
| D14 | Bump commits to main via GitHub Contents API (GitHub-signed, Verified). gh-pages keeps plain `git push`. |
| D15 | Bump opt-in via `Chart.yaml` annotation `0ekk.github.io/upstream-repo: <owner/repo>`; generic `scripts/bump.sh`; tag lookup shared in `scripts/lib.sh`. |
| D12 | Delete the 17 old `v4.x` GitHub Releases + tags (list first). |

## Target layout (main)

```
charts/
  code-server/provision.sh
  distribution/
    Chart.yaml  values.yaml  README.md  .helmignore
    ci/private-values.yaml  ci/proxy-values.yaml  ci/gc-values.yaml
    templates/_helpers.tpl  secret.yaml  deployment.yaml  service.yaml  pvc.yaml
              ingress.yaml  servicemonitor.yaml  serviceaccount.yaml
              gc-cronjob.yaml  gc-rbac.yaml  NOTES.txt  tests/test-connection.yaml
scripts/lib.sh  build.sh  bump.sh  publish.sh  test-lib.sh
.github/workflows/release.yaml      (replaces sync-code-server-chart.yml — deleted)
docs/plan/2026-09-18-helm-charts-repo.md
AGENTS.md   CLAUDE.md -> AGENTS.md   README.md (rewritten)
```

## Scripts (bash, `set -euo pipefail`, runnable locally)

- `scripts/lib.sh` (sourced)
  - `latest_stable_tag <owner/repo> [major]` → prints newest tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$`
    (optionally `^v<major>\.`), via `git ls-remote --tags --refs --sort=-v:refname` (logic lifted
    from the current workflow, stricter filter).
  - `next_chart_version <chart_ver> <old_app> <new_app>` → patch+1 if old/new app share
    major.minor, else minor+1 with patch 0.
- `scripts/test-lib.sh`: assert-based self-check for `next_chart_version` (e.g.
  `0.1.0 3.1.1 3.1.2 → 0.1.1`, `0.1.3 3.1.2 3.2.0 → 0.2.0`).
- `charts/code-server/provision.sh <out-dir>`: tag = `latest_stable_tag coder/code-server`;
  sparse-clone `ci/helm-chart` at tag into a temp dir; `helm lint`;
  `helm package --version X --app-version X -d <out-dir>` (X = tag without `v`, same as today).
- `scripts/build.sh <out-dir>`: for each `charts/*/`: enforce D2; source chart → `helm lint`,
  `helm template` per `ci/*-values.yaml` (and defaults) piped to `kubeconform -strict`
  (CRD catalog schema location for ServiceMonitor), `helm package -d <out-dir>`;
  provisioned → `bash provision.sh <out-dir>`.
- `scripts/bump.sh`: for each `charts/*/Chart.yaml` with the upstream annotation: compare
  `appVersion` with `latest_stable_tag repo <current major>`; if newer, set `appVersion` and
  `version = next_chart_version …` with `yq -i`; if a newer major exists, emit `::warning::`.
  Prints changed `Chart.yaml` paths. Edits the working tree only.
- `scripts/publish.sh <dist-dir>`: `git worktree` of `gh-pages`; copy each `<dist>/*.tgz` not
  already present (existing = immutable, `::notice::` skip); if nothing new and every index
  URL already starts with `$CHART_REPO_URL/` → exit. Otherwise `helm repo index gh-pages --url
  $CHART_REPO_URL` (no `--merge`: the tgz set is the source of truth, which also rewrites the
  old URLs — D1 needs no special migration step), regenerate `gh-pages/README.md` (chart list
  from `index.yaml`, `helm repo add 0ekk …`), commit as github-actions[bot], push.
  `CHART_REPO_URL` defaults to `https://${GITHUB_REPOSITORY_OWNER}.github.io/${repo}`.

## Workflow `.github/workflows/release.yaml`

Triggers: push to main, pull_request, daily cron `0 0 * * *`, workflow_dispatch.
`permissions: contents: write`; `concurrency: release` (no cancel). One job, ubuntu-latest:

1. checkout (fetch-depth 0); `azure/setup-helm@v4` pinned `v4.3.0`; install pinned kubeconform.
2. `scripts/test-lib.sh`.
3. schedule/dispatch only: `scripts/bump.sh` → step output of changed Chart.yaml paths.
4. `scripts/build.sh dist`.
5. kind tests if event is push/PR or a bump happened: `helm/kind-action`, then for each source
   chart and each `ci/*-values.yaml`: `helm install --wait --timeout 3m` → `helm test` → uninstall.
6. main + bump happened: per changed file `gh api -X PUT repos/$GITHUB_REPOSITORY/contents/<path>`
   with `content=$(base64 -w0 <path>)`, `sha=$(git rev-parse HEAD:<path>)`, `branch=main`,
   message `Bump <chart> to <appVersion>`. Failure aborts before publish (retried next day).
7. main (non-PR): `scripts/publish.sh dist`.

Order bump → validate → commit → publish in one run is required: pushes made with
`GITHUB_TOKEN` don't trigger workflows, and a failed validation must not land a bump on main.

## distribution chart

- `Chart.yaml`: apiVersion v2, `name: distribution`, `version: 0.1.0`, `appVersion: "3.1.1"`,
  `sources`, annotation `0ekk.github.io/upstream-repo: distribution/distribution`.
- Image `docker.io/library/registry`, tag defaults to `.Chart.AppVersion`.
- Config: helper `distribution.config` = `mustMergeOverwrite (default dict) .Values.config`.
  Defaults: `version: 0.1`, `http.addr: :5000`, `http.debug.addr: :5001`,
  `http.debug.prometheus.enabled: <metrics.enabled>`, `storage.delete.enabled: true`,
  `health.storagedriver.enabled: true`. Add `storage.filesystem.rootdirectory:
  /var/lib/registry` only when user `config.storage` sets none of
  filesystem/s3/gcs/azure/inmemory (avoids two drivers after merge). htpasswd helper adds
  `auth.htpasswd.{realm,path}` and mounts `auth.htpasswd.existingSecret`/`secretKey`.
  Rendered to Secret key `config.yml`, mounted at `/etc/distribution/config.yml`;
  pod annotation `checksum/config` for rollouts.
- Deployment: replicas `replicaCount` (default 1), `strategy: Recreate` when filesystem
  storage or GC; `fail` if GC enabled and replicaCount ≠ 1. Pod securityContext uid/gid 1000,
  fsGroup 1000, runAsNonRoot, seccomp RuntimeDefault; container readOnlyRootFilesystem,
  no privilege escalation, drop ALL. Probes: tcpSocket on 5000 (works with auth/TLS).
  Default resources requests set. `extraEnv`, `extraVolumes`, `extraVolumeMounts`,
  nodeSelector/tolerations/affinity.
- PVC when filesystem storage and `persistence.enabled` (default true, 10Gi,
  `existingClaim`, `storageClass`, `accessModes`).
- Service ClusterIP 5000; port `metrics` 5001 when `metrics.enabled`. Optional
  ServiceMonitor (`metrics.serviceMonitor.enabled`). Optional Ingress (className,
  annotations, hosts, tls; README notes nginx body-size annotation).
- GC (`gc.enabled`, `gc.schedule`, `gc.deleteUntagged: false`): initContainer same image,
  same config/volumes, `sh -c 'registry garbage-collect [--delete-untagged]
  /etc/distribution/config.yml || echo "garbage-collect failed" >&2'`. CronJob
  `registry.k8s.io/kubectl` (runAsUser 65532) runs `rollout restart deployment/<fullname>`;
  ServiceAccount + Role (`apps/deployments` get,patch, resourceNames fullname) + RoleBinding;
  `concurrencyPolicy: Forbid`.
- `helm test`: pod using the registry image, `wget -qO- http://<svc>:5000/v2/`.
- `ci/`: private (defaults), proxy (`config.proxy.remoteurl: https://registry-1.docker.io`,
  `ttl: 168h`), gc (`gc.enabled: true`). `.helmignore` excludes `ci/`.
- README: values table, examples (S3 via extraEnv, proxy, htpasswd), GC semantics
  (runs on every pod start; downtime = GC duration), one-release-per-upstream note.

## Docs

- `docs/plan/2026-09-18-helm-charts-repo.md`: rationale, D1–D15, impact (URL change, releases
  removed, bot commits), verification results.
- `AGENTS.md` (+ `ln -s AGENTS.md CLAUDE.md`): layout rules, add-a-chart steps, "bump chart
  version on every source chart change — published versions are immutable", upstream
  annotation, local test commands, signed commits.
- `README.md`: `helm repo add 0ekk https://0ekk.github.io/helm-charts`, chart table
  (name, kind, upstream), how publishing works.

## Rollout order

1. Implement on local main; run verification steps 1–3 below.
2. Confirm with user, then `gh repo rename helm-charts --repo 0ekk/code-server-chart` and
   `git remote set-url origin https://github.com/0ekk/helm-charts.git`.
3. GPG-signed commit(s), push main → release.yaml publishes distribution 0.1.0, skips
   code-server 4.137.0, reindexes all 18 entries under the new URL.
4. List old releases, confirm, `gh release delete <tag> --cleanup-tag -y` for each of the 17.
5. User renames local dir `~/proj/code-server-chart` → `~/proj/helm-charts` afterwards.

## Verification

1. `bash scripts/test-lib.sh` passes; `shellcheck scripts/*.sh charts/*/provision.sh` if available.
2. `scripts/build.sh /tmp/dist` locally → `code-server-4.137.0.tgz`, `distribution-0.1.0.tgz`;
   kubeconform clean.
3. Local kind: `kind create cluster`; install each `ci/*-values.yaml`, `helm test` passes;
   check pod runs as uid 1000 with read-only rootfs; gc scenario logs garbage-collect
   output in the initContainer; `kubectl create job --from=cronjob/…` restarts the Deployment.
   Push/pull an image through a port-forward to the private scenario (`docker push localhost:5000/…`).
4. Publish dry-run: in a scratch clone whose `origin` is a local bare copy of the repo, run
   `CHART_REPO_URL=https://0ekk.github.io/helm-charts scripts/publish.sh /tmp/dist` → bare
   gh-pages index has 18 entries, all URLs under the new base; second run is a no-op.
5. After rollout: Actions run green; `helm repo add 0ekk https://0ekk.github.io/helm-charts &&
   helm search repo 0ekk -l` shows both charts; manual `workflow_dispatch` is a no-op.
6. Bump path: temporarily set `appVersion: "3.1.0"` on a scratch branch, run `scripts/bump.sh`
   → `3.1.1`, version `0.1.1` (verified locally; the Contents API step is exercised on the
   first real upstream release).

Skipped: source-chart "forgot to bump" detection (skip + notice only; add a content diff
check if it bites), values.schema.json, OCI push, LICENSE.

## Verification results (2026-09-18)

Ran locally against a pinned `kubeconform v0.7.0` binary (not preinstalled;
CI installs the same pinned version) and a scratch `kind` cluster:

1. `scripts/test-lib.sh` passes (3 assertions on `next_chart_version`).
   `shellcheck` clean on `scripts/*.sh` and `charts/code-server/provision.sh`
   (only an SC1091 info note about not following a relative `source`, expected).
2. `scripts/build.sh /tmp/dist` produced `code-server-4.137.0.tgz` (via live
   sparse-checkout of `coder/code-server`'s `ci/helm-chart` at the current
   latest tag) and `distribution-0.1.0.tgz`; every rendered manifest
   (defaults + all three `ci/*-values.yaml` + a metrics/ServiceMonitor/ingress
   combo) validated clean against `kubeconform -strict` using the
   `datreeio/CRDs-catalog` schema source for the `ServiceMonitor` CRD.
3. `kind` cluster, all three `ci/*-values.yaml` scenarios installed and
   `helm test` passed:
   - private: pod runs as uid/gid 1000 with `readOnlyRootFilesystem: true`;
     pushed and pulled a real image (`busybox`) through a port-forward.
   - gc: initContainer ran `registry garbage-collect`, failed on the empty
     repo (nothing to collect yet), logged to stderr, and did **not** block
     the main container from starting or `helm test` from passing —
     confirms D9's "GC failure logs, never blocks startup". Manually
     triggered the CronJob's Job template; the scoped RBAC (Role limited by
     `resourceNames` to the one Deployment) was sufficient for
     `kubectl rollout restart`, confirmed via the
     `kubectl.kubernetes.io/restartedAt` annotation appearing.
   - proxy: installs and passes `helm test` with `config.proxy.remoteurl` set.
4. Publish dry run: seeded a scratch bare repo's `gh-pages` from the real
   `origin/gh-pages` (17 code-server entries under the old URL), ran
   `CHART_REPO_URL=https://0ekk.github.io/helm-charts scripts/publish.sh` —
   resulting `index.yaml` has all 18 entries (17 code-server + 1
   distribution), every URL rewritten under the new base, README
   regenerated; a second run correctly no-ops.
5. Not run (needs the actual rename): Actions-run-green and
   `helm search repo` checks.
6. Bump path: on a scratch branch, set `distribution`'s `appVersion` to
   `3.1.0` and ran `scripts/bump.sh` → bumped to `appVersion: 3.1.1`,
   `version: 0.1.1` (patch→patch, matching D11/D13). The GitHub Contents
   API commit step is exercised on the first real upstream release.

Remaining before rollout: repo owner review of the diff, then rollout steps
2–5 (rename, first push, old-release cleanup) as documented above.

Rollout completed 2026-09-18: repo renamed to `0ekk/helm-charts`, `main`
pushed (release.yaml ran green), `gh-pages` reindexed under the new URL,
17 old `v4.x` releases + tags deleted.

## Addendum: per-component gh-pages layout (2026-09-18)

**Rationale**: all `.tgz` packages were published flat at the `gh-pages`
root (`code-server-4.137.0.tgz`, `distribution-0.1.0.tgz`, …). As more
charts get added this becomes hard to browse and invites filename
collisions across unrelated charts. Requested by the repo owner.

**Decision**: `dist/` (the output of `scripts/build.sh`) and `gh-pages` both
organize packages as `<component>/<component>-<version>.tgz` instead of a
flat directory. `helm repo index` walks subdirectories natively and encodes
the relative path in each entry's `urls`, so `index.yaml` needs no other
change; `scripts/publish.sh`'s "skip if already published" and
"index already up to date" checks now key off the per-component path
instead of the bare filename.

**Impact**:
- `scripts/build.sh`: source charts package into `<out-dir>/<name>/`;
  provisioned charts get `<out-dir>/<name>/` as their own `<out-dir>` arg
  (their contract — "package into the given directory" — didn't need to
  change).
- `scripts/publish.sh`: copies `<dist-dir>/<component>/*.tgz` into
  `gh-pages/<component>/`, preserving the split.
- One-time migration of the 18 already-published packages on `gh-pages`
  from the flat layout into `code-server/` and `distribution/`, done
  directly against the live branch (not scripted into the repo — it only
  ever needs to run once; every future publish already lands in the
  right place). `index.yaml` was regenerated afterward so its `urls`
  match the new paths.
- No change to the chart-repo add command, `index.yaml`'s schema, or any
  chart's own contents — only where the `.tgz` files live.

**Verified**: `helm repo index` confirmed locally to emit correct relative
subdirectory URLs; `scripts/build.sh` produces the new layout end-to-end;
`scripts/publish.sh` tested against a scratch bare repo seeded with an
already-migrated `gh-pages` — steady state is a no-op, and a new version
correctly lands under its component directory with no duplicate index
entries. The real migration + reindex was applied to the live `gh-pages`
branch and checked with `helm repo update && helm search repo`.

## Addendum: validate the packaged tgz, scope kind tests to changed charts (2026-09-18)

**Rationale**: `scripts/build.sh` only ran `helm lint` + kubeconform against a
source chart's source tree; a provisioned chart got none of that — only
whatever `helm lint` its own `provision.sh` happened to call, on the
upstream source tree, never on the actual package it produces. That's an
asymmetry between the two integration paths with no technical reason behind
it. Separately, the kind-install + `helm test` step always swept every
source chart's every `ci/*-values.yaml` scenario on every push/PR, which
doesn't scale as chart and scenario counts grow.

**Decisions**:
- `scripts/build.sh` now validates the *packaged* `.tgz` — for both source
  and provisioned charts — instead of the source tree. Since this Helm
  build only accepts chart directories (not archives) for `lint`/`template`,
  it unpacks the just-produced `.tgz` into a temp dir and lints/templates
  that. This is why a provisioned chart's `ci/*-values.yaml` (if it ever
  gets one) would already be picked up for free — the loop keys off
  `<chart-dir>/ci/*-values.yaml` regardless of chart kind.
- The kind-install + `helm test` step is now scoped to only the *source*
  chart directories that changed in the current push/PR/scheduled bump
  (including newly-added ones), not every source chart every run.
  Provisioned charts stay out of scope for kind testing — they don't carry
  a local `templates/tests/*.yaml` hook or `ci/` scenarios by contract
  (AGENTS.md's provisioned-chart shape is just `provision.sh`), so there's
  nothing chart-repo-local to install-test yet; only the lint/kubeconform
  pass (previous decision) applies to them today.
- "Changed" is computed per trigger: `git diff --name-only` against
  `github.event.before` for `push` (falling back to "everything under
  `charts/`" when `before` isn't a resolvable commit, e.g. a repo's first
  push), against `github.event.pull_request.base.sha` for `pull_request`,
  and from `scripts/bump.sh`'s own changed-`Chart.yaml` list for
  `schedule`/`workflow_dispatch` (already exactly the source charts a bump
  touched).

**Impact**: `code-server`'s packaged chart now gets the same kubeconform
pass `distribution` gets. CI no longer re-installs every scenario of every
source chart on every push — only what actually changed. A commit that
only touches `scripts/` or docs skips the kind cluster + install steps
entirely.

**Verified**: confirmed locally that this Helm build's `lint`/`template`
reject `.tgz` paths directly (`invalid chart URL format`), which is why the
unpack-then-lint approach is needed; `scripts/build.sh` re-run end to end
now shows `code-server`'s package going through the same kubeconform check
as `distribution`. The "changed dirs" logic was rehearsed standalone against
real repo history for all four branches: a push whose diff touched only
`scripts/` (correctly empty — the exact regression this addendum's local
rehearsal caught: `grep -o` finding no match combined with
`set -o pipefail` was aborting the step whenever nothing changed, fixed by
wrapping the grep in `{ ... || true; }`), a push with no resolvable `before`
(all current charts reported), a schedule with a bump touching one chart,
and a schedule with no bump. Not verified: an actual GitHub-hosted
`pull_request` event and a real `push` with a genuine `before` SHA, since
those need real CI context — checked on the next real push/PR instead.
