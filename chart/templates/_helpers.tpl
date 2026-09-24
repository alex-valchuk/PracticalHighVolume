{{/*
Common name prefix.
*/}}
{{- define "flights.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base name: just the release name, e.g. "flights".
Used for resource names to avoid "flights-flights-platform-xxx" duplication.
*/}}
{{- define "flights.baseName" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full name for backward compatibility (same as baseName).
*/}}
{{- define "flights.fullname" -}}
{{- include "flights.baseName" . -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "flights.labels" -}}
app.kubernetes.io/name: {{ include "flights.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: flights-platform
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Postgres connection string (used by API and workers).
*/}}
{{- define "flights.postgresConnection" -}}
Host={{ include "flights.fullname" . }}-postgres;Port={{ .Values.postgres.port }};Database={{ .Values.postgres.database }};Username={{ .Values.postgres.user }};Password={{ .Values.secrets.postgresPassword }}
{{- end -}}

{{/*
RabbitMQ host (K8s service name).
*/}}
{{- define "flights.rabbitHost" -}}
{{ include "flights.fullname" . }}-rabbitmq
{{- end -}}

{{/*
Jaeger OTLP endpoint.
*/}}
{{- define "flights.jaegerOtlp" -}}
http://{{ include "flights.fullname" . }}-jaeger:{{ .Values.jaeger.otlpGrpcPort }}
{{- end -}}