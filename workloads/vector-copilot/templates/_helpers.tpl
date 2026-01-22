{{/*
Expand the name of the chart.
*/}}
{{- define "vector-copilot.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vector-copilot.fullname" -}}
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
{{- define "vector-copilot.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vector-copilot.labels" -}}
helm.sh/chart: {{ include "vector-copilot.chart" . }}
{{ include "vector-copilot.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vector-copilot.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vector-copilot.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vector-copilot.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vector-copilot.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the ConfigMap
*/}}
{{- define "vector-copilot.configMapName" -}}
{{- printf "%s-config" (include "vector-copilot.fullname" .) }}
{{- end }}

{{/*
Create the name of the PVC
*/}}
{{- define "vector-copilot.pvcName" -}}
{{- printf "%s-data" (include "vector-copilot.fullname" .) }}
{{- end }}
