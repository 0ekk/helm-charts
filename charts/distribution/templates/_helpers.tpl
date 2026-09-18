{{/*
Chart name, truncated to fit Kubernetes name limits.
*/}}
{{- define "distribution.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full resource name: <release>-<chart name>, or fullnameOverride if set.
*/}}
{{- define "distribution.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "distribution.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "distribution.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "distribution.selectorLabels" -}}
app.kubernetes.io/name: {{ include "distribution.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "distribution.serviceAccountName" -}}
{{ include "distribution.fullname" . }}
{{- end -}}

{{/*
True when .Values.config.storage already picks a driver, so the chart's
filesystem default must not be added on top of it.
*/}}
{{- define "distribution.hasUserStorageDriver" -}}
{{- $storage := (.Values.config.storage | default dict) -}}
{{- $found := false -}}
{{- range list "filesystem" "s3" "gcs" "azure" "inmemory" -}}
{{- if hasKey $storage . -}}{{- $found = true -}}{{- end -}}
{{- end -}}
{{- $found -}}
{{- end -}}

{{/*
Whether the effective config ends up using filesystem storage (chart default
or explicit user choice) — deployment.yaml uses this to decide on the PVC
mount and the Recreate strategy.
*/}}
{{- define "distribution.usesFilesystemStorage" -}}
{{- if ne (include "distribution.hasUserStorageDriver" .) "true" -}}
true
{{- else if hasKey (.Values.config.storage | default dict) "filesystem" -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Effective registry config: chart defaults deep-merged with .Values.config,
plus the htpasswd helper. Rendered as YAML into the config Secret.
*/}}
{{- define "distribution.config" -}}
{{- $cfg := dict "version" "0.1" -}}
{{- $_ := set $cfg "http" (dict "addr" ":5000" "debug" (dict "addr" ":5001" "prometheus" (dict "enabled" .Values.metrics.enabled))) -}}
{{- $_ := set $cfg "storage" (dict "delete" (dict "enabled" true)) -}}
{{- $_ := set $cfg "health" (dict "storagedriver" (dict "enabled" true)) -}}
{{- if ne (include "distribution.hasUserStorageDriver" .) "true" -}}
{{- $_ := set (index $cfg "storage") "filesystem" (dict "rootdirectory" "/var/lib/registry") -}}
{{- end -}}
{{- $cfg = mustMergeOverwrite $cfg (.Values.config | default dict) -}}
{{- if .Values.auth.htpasswd.enabled -}}
{{- $existingAuth := (index $cfg "auth") | default dict -}}
{{- $_ := set $cfg "auth" (mustMergeOverwrite $existingAuth (dict "htpasswd" (dict "realm" .Values.auth.htpasswd.realm "path" "/etc/distribution/htpasswd"))) -}}
{{- end -}}
{{- toYaml $cfg -}}
{{- end -}}
