{{/*
Reusable name for telemetry-related chart resources.
*/}}
{{- define "retool.telemetry.fullname" -}}
{{- $name := default "telemetry" .Values.telemetry.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels to include on telemetry pods.
*/}}
{{- define "retool.telemetry.labels" -}}
helm.sh/chart: {{ include "retool.chart" . }}
{{ include "retool.telemetry.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Labels to use as selector for telemetry pods and deployment. Note these become
immutable once deployed, so changes here will require recreating the deployment.
*/}}
{{- define "retool.telemetry.selectorLabels" -}}
app.kubernetes.io/name: {{ default "telemetry" .Values.telemetry.nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}


{{/*
The name of the service account to use.
*/}}
{{- define "retool.telemetry.serviceAccountName" -}}
{{- if .Values.telemetry.serviceAccount.create }}
{{- default (include "retool.telemetry.fullname" .) .Values.telemetry.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.telemetry.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
The labels to use for scoping log collection to only the pods in the same 
release, as a single comma-separated string. The label(s) below should be
present on all relevant pods, or else logs won't be collected. */}}
{{- define "retool.telemetry.logSourcePodLabels" -}}
app.kubernetes.io/instance={{ .Release.Name }}
{{- end }}


{{/*
Env vars to include on retool pods to collect telemetry via telemetry pod.
*/}}
{{- define "retool.telemetry.includeEnvVars" -}}
{{- if .Values.telemetry.enabled }}
- name: RTEL_ENABLED
  value: 'true'
- name: RTEL_SERVICE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['telemetry.retool.com/service-name']
- name: K8S_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: K8S_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: STATSD_HOST
  value: {{ printf "%s.%s" (include "retool.telemetry.fullname" .) .Release.Namespace | quote }}
- name: STATSD_PORT
  value: "9125"
{{- end }}
{{- end }}
