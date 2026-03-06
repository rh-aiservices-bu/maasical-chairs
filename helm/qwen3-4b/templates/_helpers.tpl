{{/*
Expand the name of the chart.
*/}}
{{- define "qwen3-4b.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
Use release name directly to avoid duplication.
*/}}
{{- define "qwen3-4b.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "qwen3-4b.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "qwen3-4b.labels" -}}
helm.sh/chart: {{ include "qwen3-4b.chart" . }}
{{ include "qwen3-4b.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: llm-inference
app.kubernetes.io/part-of: qwen-stack
{{- end }}

{{/*
Selector labels
*/}}
{{- define "qwen3-4b.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qwen3-4b.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "qwen3-4b.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "qwen3-4b.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
