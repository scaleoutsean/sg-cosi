{{/*
Expand the name of the chart.
*/}}
{{- define "sg-cosi-driver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sg-cosi-driver.fullname" -}}
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
{{- define "sg-cosi-driver.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "sg-cosi-driver.labels" -}}
helm.sh/chart: {{ include "sg-cosi-driver.chart" . }}
{{ include "sg-cosi-driver.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (immutable, used in Deployment matchLabels).
*/}}
{{- define "sg-cosi-driver.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sg-cosi-driver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "sg-cosi-driver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sg-cosi-driver.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the driver container image reference.
*/}}
{{- define "sg-cosi-driver.driverImage" -}}
{{- $tag := .Values.driver.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.driver.image.repository $tag }}
{{- end }}

{{/*
Create the sidecar container image reference.
*/}}
{{- define "sg-cosi-driver.sidecarImage" -}}
{{- printf "%s:%s" .Values.sidecar.image.repository .Values.sidecar.image.tag }}
{{- end }}

{{/*
Resolve the COSI driver name (required).
*/}}
{{- define "sg-cosi-driver.driverName" -}}
{{- required "driver.name is required" .Values.driver.name }}
{{- end }}

{{/*
BucketClass name (short default).
*/}}
{{- define "sg-cosi-driver.bucketClassName" -}}
{{- .Values.bucketClass.name | default "storagegrid" }}
{{- end }}

{{/*
BucketAccessClass name (short default).
*/}}
{{- define "sg-cosi-driver.bucketAccessClassName" -}}
{{- .Values.bucketAccessClass.name | default "storagegrid" }}
{{- end }}

{{/*
Resolve the storagegrid S3 API endpoint.
*/}}
{{- define "sg-cosi-driver.s3Endpoint" -}}
{{- if .Values.storagegrid.s3Endpoint }}
{{- .Values.storagegrid.s3Endpoint }}
{{- else }}
{{- printf "http://%s:%v" .Values.storagegrid.serviceName (.Values.storagegrid.s3Port | int) }}
{{- end }}
{{- end }}

{{/*
Resolve the storagegrid Admin API endpoint.
*/}}
{{- define "sg-cosi-driver.adminEndpoint" -}}
{{- if .Values.storagegrid.adminEndpoint }}
{{- .Values.storagegrid.adminEndpoint }}
{{- else }}
{{- printf "http://%s:%v" .Values.storagegrid.serviceName (.Values.storagegrid.adminPort | int) }}
{{- end }}
{{- end }}
