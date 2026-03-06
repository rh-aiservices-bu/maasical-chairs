{{/*
Expand the name of the chart.
*/}}
{{- define "granite4-micro.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
Use release name directly to avoid duplication.
*/}}
{{- define "granite4-micro.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "granite4-micro.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "granite4-micro.labels" -}}
helm.sh/chart: {{ include "granite4-micro.chart" . }}
{{ include "granite4-micro.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: llm-inference
app.kubernetes.io/part-of: granite-stack
{{- end }}

{{/*
Selector labels
*/}}
{{- define "granite4-micro.selectorLabels" -}}
app.kubernetes.io/name: {{ include "granite4-micro.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "granite4-micro.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "granite4-micro.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
