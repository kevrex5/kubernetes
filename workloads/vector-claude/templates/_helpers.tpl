{{/*
Expand the name of the chart.
*/}}
{{- define "vector-syslog.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "vector-syslog.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vector-syslog.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vector-syslog.labels" -}}
helm.sh/chart: {{ include "vector-syslog.chart" . }}
{{ include "vector-syslog.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vector-syslog.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vector-syslog.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vector-syslog.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vector-syslog.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "vector-syslog.configMapName" -}}
{{- printf "%s-config" (include "vector-syslog.fullname" .) }}
{{- end }}

{{/*
PVC name
*/}}
{{- define "vector-syslog.pvcName" -}}
{{- printf "%s-data" (include "vector-syslog.fullname" .) }}
{{- end }}

{{/*
Build hash key expression from keyFields
This concatenates the specified fields to create a stable hash key
*/}}
{{- define "vector-syslog.hashKeyExpression" -}}
{{- $fields := .Values.hashSplit.keyFields -}}
{{- $expressions := list -}}
{{- range $field := $fields -}}
{{- $expressions = append $expressions (printf "to_string(%s) ?? \"\"" $field) -}}
{{- end -}}
{{- join " + \"|\" + " $expressions -}}
{{- end }}
