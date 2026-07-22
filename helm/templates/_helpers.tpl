{{/*
_helpers.tpl — Helm Template Helper Functions

WHY THIS FILE EXISTS:
  Other templates reference helper functions like:
    {{ include "employee-service.fullname" . }}
    {{ include "employee-service.labels" . }}

  These helpers compute values that are needed in MULTIPLE templates.
  Without _helpers.tpl, you'd copy-paste these expressions into every template.
  The underscore prefix (_helpers.tpl) tells Helm this file is NOT rendered
  directly as a Kubernetes manifest — it's a library of functions only.

  Files beginning with _ are "partials" — not rendered, only included.
  Files without _ are rendered and applied to the cluster.
*/}}

{{/*
employee-service.fullname:
  Generates the full release name: "release-chart-name"
  If the release name already contains the chart name, don't duplicate it.
  Why? "myapp-employee-service" is clearer than "myapp-employee-service-employee-service".
  truncate 63: Kubernetes names must be <= 63 characters (DNS label limit).
  trimSuffix "-": remove trailing dash that could appear from truncation.
*/}}
{{- define "employee-service.fullname" -}}
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
employee-service.chart:
  Generates the chart label: "chart-name-chart-version"
  Used to identify which chart version created these resources.
  Helps with debugging: "which chart version deployed this pod?"
*/}}
{{- define "employee-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
employee-service.labels:
  Standard Kubernetes recommended labels (https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
  Applied to ALL Kubernetes objects created by this chart.

  Why standard labels?
    - Tooling (Lens, k9s, Helm, kubectl) understands these labels
    - `kubectl get all -l app.kubernetes.io/instance=myapp` returns all related resources
    - Helm uses these to track which resources belong to which release
    - `helm uninstall` deletes all resources with the release label
*/}}
{{- define "employee-service.labels" -}}
helm.sh/chart: {{ include "employee-service.chart" . }}
{{ include "employee-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: employee-platform
{{- end }}

{{/*
employee-service.selectorLabels:
  Labels used by the Service's selector to find pods.
  These MUST NOT change after deployment — changing selector labels
  requires deleting and recreating the Service.

  name: the application name (employee-service)
  instance: the Helm release name (allows multiple installs of same chart)
*/}}
{{- define "employee-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "employee-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
employee-service.name:
  Returns the chart name, truncated to 63 characters.
*/}}
{{- define "employee-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
employee-service.serviceAccountName:
  Returns the ServiceAccount name to use.
  If create=true: use the generated name.
  If create=false: use whatever name is configured (or "default").
*/}}
{{- define "employee-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "employee-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
