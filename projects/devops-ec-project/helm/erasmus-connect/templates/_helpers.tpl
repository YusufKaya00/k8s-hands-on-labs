{{/*
Chart tam adını oluşturur (ör. release-erasmus-connect).
*/}}
{{- define "erasmus-connect.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Ortak Kubernetes etiketleri (labels).
*/}}
{{- define "erasmus-connect.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
