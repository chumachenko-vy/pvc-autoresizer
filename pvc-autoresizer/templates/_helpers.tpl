{{/*
Expand the name of the chart.
*/}}
{{- define "pvc-autoresizer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "pvc-autoresizer.fullname" -}}
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
{{- define "pvc-autoresizer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pvc-autoresizer.labels" -}}
helm.sh/chart: {{ include "pvc-autoresizer.chart" . }}
{{ include "pvc-autoresizer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pvc-autoresizer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pvc-autoresizer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pvc-autoresizer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s-annotator" (include "pvc-autoresizer.fullname" .)) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Convert storage limit to bytes for PrometheusRule
*/}}
{{- define "pvc-autoresizer.storageLimitBytes" -}}
{{- $limit := .Values.annotator.storageLimit -}}
{{- if hasSuffix "Ti" $limit -}}
{{- printf "%d" (mul (int (trimSuffix "Ti" $limit)) 1099511627776) -}}
{{- else if hasSuffix "Gi" $limit -}}
{{- printf "%d" (mul (int (trimSuffix "Gi" $limit)) 1073741824) -}}
{{- else if hasSuffix "Mi" $limit -}}
{{- printf "%d" (mul (int (trimSuffix "Mi" $limit)) 1048576) -}}
{{- else -}}
{{- $limit -}}
{{- end -}}
{{- end }}
