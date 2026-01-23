{{/*
Expand the name of the chart.
*/}}
{{- define "vector-azure-simple.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vector-azure-simple.fullname" -}}
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
{{- define "vector-azure-simple.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vector-azure-simple.labels" -}}
helm.sh/chart: {{ include "vector-azure-simple.chart" . }}
{{ include "vector-azure-simple.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vector-azure-simple.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vector-azure-simple.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vector-azure-simple.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vector-azure-simple.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ConfigMap name
*/}}
{{- define "vector-azure-simple.configMapName" -}}
{{- printf "%s-config" (include "vector-azure-simple.fullname" .) }}
{{- end }}

{{/*
PVC name
*/}}
{{- define "vector-azure-simple.pvcName" -}}
{{- printf "%s-data" (include "vector-azure-simple.fullname" .) }}
{{- end }}
