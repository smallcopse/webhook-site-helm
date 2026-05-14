{{/*
Expand the name of the chart.
*/}}
{{- define "webhook-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "webhook-site.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Derive APP_URL from route settings.
Uses https:// when TLS is enabled, http:// otherwise.
*/}}
{{- define "webhook-site.appUrl" -}}
{{- if .Values.route.tls.enabled -}}
https://{{ .Values.route.host }}
{{- else -}}
http://{{ .Values.route.host }}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "webhook-site.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
