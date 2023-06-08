{{/*
Reusable name for vector-related chart resources.
*/}}
{{- define "retool.vector.fullname" -}}
{{- $name := default "vector" .Values.vector.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels to include on vector resources.
*/}}
{{- define "retool.vector.labels" -}}
helm.sh/chart: {{ include "retool.chart" . }}
{{ include "retool.vector.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Labels to include on vector resources.
*/}}
{{- define "retool.vector.selectorLabels" -}}
app.kubernetes.io/name: {{ default "vector" .Values.vector.nameOverride }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}


{{/*
The name of the service account to use.
*/}}
{{- define "retool.vector.serviceAccountName" -}}
{{- if .Values.vector.serviceAccount.create }}
{{- default (include "retool.vector.fullname" .) .Values.vector.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.vector.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
The labels to use for scoping vector to only the pods in the same release, as a
single string. The format is different, but the labels and values should track the
"retool.selectorLabels" partial.
*/}}
{{- define "retool.vector.logSourcePodLabels" -}}
app.kubernetes.io/name={{ include "retool.name" . }},app.kubernetes.io/instance={{ .Release.Name }}
{{- end }}


# {{/*
# Spec parts common to init-auth and refresh-auth containers
# */}}
# {{- define "retool.vector.authContainer" -}}
# image: 'alpine:latest'
# command: ["/bin/sh"]
# restartPolicy: OnError
# env:
#   - name: LICENSING_SERVER_URL
#     # TODO: point this at real server
#     value: "http://172.19.0.1:5001"
#   # TODO: make this a reusable partial
#   {{- if and (not .Values.externalSecrets.enabled) (not .Values.externalSecrets.externalSecretsOperator.enabled) }}
#   - name: LICENSE_KEY
#     valueFrom:
#       secretKeyRef:
#         {{- if .Values.config.licenseKeySecretName }}
#         name: {{ .Values.config.licenseKeySecretName }}
#         key: {{ .Values.config.licenseKeySecretKey | default "license-key" }}
#         {{- else }}
#         name: {{ template "retool.fullname" . }}
#         key: license-key
#         {{- end }}
#   {{- end }}
# volumeMounts:
#   - name: config
#     mountPath: "/etc/vector-static/"
#     readOnly: true
#   - name: config-derived
#     mountPath: "/etc/vector/"
#   - name: telemetry-auth
#     mountPath: "/etc/vector-telemetry-auth"
# {{- end }}


# {{/*
# Common config for telemetry containers (init, vector)
# */}}
# {{- define "retool.vector.containerCommon" -}}
# image: '{{ .Values.vector.image.repository }}:{{ include "retool.vector.imageTag" . }}'
# imagePullPolicy: {{ .Values.vector.image.pullPolicy }}
# {{- end }}
