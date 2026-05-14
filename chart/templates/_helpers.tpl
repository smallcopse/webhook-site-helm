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
Priority:
  1. webhook.appUrl (explicit override)
  2. route.host     (explicit hostname)
  3. IngressController lookup → auto-assigned OpenShift hostname
       format: <route-name>-<namespace>.<ingresscontroller.status.domain>
  4. empty string   (APP_URL env var is omitted from the Deployment)
*/}}
{{- define "webhook-site.appUrl" -}}
{{- $scheme := "http" -}}
{{- if .Values.route.tls.enabled -}}{{- $scheme = "https" -}}{{- end -}}
{{- if .Values.webhook.appUrl -}}
{{ .Values.webhook.appUrl }}
{{- else if .Values.route.host -}}
{{ $scheme }}://{{ .Values.route.host }}
{{- else -}}
{{- $ic := lookup "operator.openshift.io/v1" "IngressController" "openshift-ingress-operator" "default" -}}
{{- if and $ic $ic.status $ic.status.domain -}}
{{- $host := printf "webhook-%s.%s" .Values.namespace $ic.status.domain -}}
{{ $scheme }}://{{ $host }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "webhook-site.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
