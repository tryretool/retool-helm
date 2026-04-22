{{/*
Expand the name of the chart.
*/}}
{{- define "retool.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "retool.fullname" -}}
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
{{- define "retool.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{- define "retool.deploymentTemplateType" -}}
{{- "k8s-helm" | quote -}}
{{- end -}}

{{- define "retool.deploymentTemplateVersion" -}}
{{- .Chart.Version | quote -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "retool.labels" -}}
helm.sh/chart: {{ include "retool.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for main backend. Note changes here will require deployment
recreation and incur downtime. The "app.kubernetes.io/instance" label should
also be included in all deployments, so telemetry knows how to find logs.
*/}}
{{- define "retool.selectorLabels" -}}
app.kubernetes.io/name: {{ include "retool.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for standalone dbconnector. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.dbconnector.selectorLabels" -}}
retoolService: {{ include "retool.dbconnector.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for standalone dbconnector.
*/}}
{{- define "retool.dbconnector.labels" -}}
app.kubernetes.io/name: {{ include "retool.dbconnector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: dbconnector
{{- end }}

{{/*
Selector labels for workflow backend. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.workflowBackend.selectorLabels" -}}
retoolService: {{ include "retool.workflowBackend.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for workflow backend.
*/}}
{{- define "retool.workflowBackend.labels" -}}
app.kubernetes.io/name: {{ include "retool.workflowBackend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: workflow-backend
{{- end }}

{{/*
Selector labels for workflow worker. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.workflowWorker.selectorLabels" -}}
retoolService: {{ include "retool.workflowWorker.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for workflow worker.
*/}}
{{- define "retool.workflowWorker.labels" -}}
app.kubernetes.io/name: {{ include "retool.workflowWorker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: workflow-worker
{{- end }}

{{/*
Selector labels for code executor. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.codeExecutor.selectorLabels" -}}
retoolService: {{ include "retool.codeExecutor.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for code executor.
*/}}
{{- define "retool.codeExecutor.labels" -}}
app.kubernetes.io/name: {{ include "retool.codeExecutor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: code-executor
{{- end }}

{{/*
Selector labels for agent worker. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.agentWorker.selectorLabels" -}}
retoolService: {{ include "retool.agentWorker.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for agent worker.
*/}}
{{- define "retool.agentWorker.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentWorker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: agent-worker
{{- end }}

{{/*
Selector labels for agent eval worker. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.agentEvalWorker.selectorLabels" -}}
retoolService: {{ include "retool.agentEvalWorker.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for agent eval worker.
*/}}
{{- define "retool.agentEvalWorker.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentEvalWorker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: agent-eval-worker
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "retool.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "retool.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "retool.postgresql.fullname" -}}
{{- $name := default "postgresql" .Values.postgresql.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Set postgresql ssl_enabled
*/}}
{{- define "retool.postgresql.ssl_enabled" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.ssl_enabled | quote -}}
{{- else -}}
{{- .Values.config.postgresql.ssl_enabled | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set postgresql host
*/}}
{{- define "retool.postgresql.host" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "retool.postgresql.fullname" . | quote -}}
{{- else -}}
{{- .Values.config.postgresql.host | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set postgresql port
*/}}
{{- define "retool.postgresql.port" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.service.port | quote -}}
{{- else -}}
{{- .Values.config.postgresql.port | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set postgresql db
*/}}
{{- define "retool.postgresql.database" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.database | quote -}}
{{- else if .Values.config.postgresql.db -}}
{{- .Values.config.postgresql.db | quote -}}
{{- else -}}
{{- .Values.config.postgresql.database | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set postgresql user
*/}}
{{- define "retool.postgresql.user" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.username | quote -}}
{{- else -}}
{{- .Values.config.postgresql.user | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set Jobs Runner enabled
Usage: (include "retool.jobRunner.enabled" .)
*/}}
{{- define "retool.jobRunner.enabled" -}}
{{- $output := "" -}}
{{- if or (gt (int (toString (.Values.replicaCount))) 1) (default false .Values.jobRunner.enabled) }}
  {{- $output = "1" -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/*
Set Workflows enabled
Usage: (include "retool.workflows.enabled" .)
*/}}
{{- define "retool.workflows.enabled" -}}
{{- $output := "" -}}
{{- $valid_retool_version_regexp := "([0-9]+\\.[0-9]+(\\.[0-9]+)?(-[a-zA-Z0-9]+)?)" }}
{{- $semver_version_regexp := "[0-9]+\\.[0-9]+(\\.[0-9]+)?" }}
{{- $retool_version_with_workflows := ( and ( regexMatch $valid_retool_version_regexp $.Values.image.tag ) ( semverCompare ">= 3.6.11-0" ( regexFind $semver_version_regexp $.Values.image.tag ) ) ) }}
{{- if or
    (eq (toString .Values.workflows.enabled) "true")
    (eq (toString .Values.workflows.enabled) "false")
-}}
  {{- if (eq (toString .Values.workflows.enabled) "true") -}}
    {{- $output = "1" -}}
  {{- else -}}
    {{- $output = "" -}}
  {{- end -}}
{{- else if empty .Values.image.tag -}}
  {{- $output = "" -}}
{{- else if eq .Values.image.tag "latest" -}}
  {{- $output = "1" -}}
{{- else if $retool_version_with_workflows -}}
  {{- $output = "1" -}}
{{- else -}}
  {{- $output = "" -}}
{{- end -}}
{{- if (eq (toString .Values.agents.enabled) "true") -}} {{/* workflows (backend) is required to use agents */}}
  {{- $output = "1" -}}
{{- end -}}
{{- if (eq (toString .Values.r2Agent.enabled) "true") -}} {{/* workflows (backend) is required to use r2 agent */}}
  {{- $output = "1" -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/*
Set agents enabled
Usage: (include "retool.agents.enabled" .)
*/}}
{{- define "retool.agents.enabled" -}}
{{- $output := "" -}}
{{- if (eq (toString .Values.agents.enabled) "true") -}}
  {{- $output = "1" -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/*
Set R2 agent enabled
Usage: (include "retool.r2Agent.enabled" .)
*/}}
{{- define "retool.r2Agent.enabled" -}}
{{- $output := "" -}}
{{- if (eq (toString .Values.r2Agent.enabled) "true") -}}
  {{- $output = "1" -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/* Global Temporal configuration */}}
{{- define "retool.temporalConfig" -}}
{{- .Values.workflows.temporal | default .Values.temporal | toYaml -}}
{{- end -}}

{{/*
Set Temporal frontend host
*/}}
{{- define "retool.temporal.host" -}}
{{- $temporalConfig := include "retool.temporalConfig" . | fromYaml -}}
{{- if $temporalConfig.enabled -}}
{{- $temporalConfig.host | quote -}}
{{- else -}}
{{- printf "%s-%s" (include "temporal.fullname" (index .Subcharts "retool-temporal-services-helm")) "frontend" -}}
{{- end -}}
{{- end -}}

{{/*
Set Temporal frontend port
*/}}
{{- define "retool.temporal.port" -}}
{{- $temporalConfig := include "retool.temporalConfig" . | fromYaml -}}
{{- if $temporalConfig.enabled -}}
{{- $temporalConfig.port | quote -}}
{{- else -}}
{{- "7233" | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set Temporal namespace
*/}}
{{- define "retool.temporal.namespace" -}}
{{- $temporalConfig := include "retool.temporalConfig" . | fromYaml -}}
{{- if $temporalConfig.enabled -}}
{{- $temporalConfig.namespace | quote -}}
{{- else -}}
{{- "workflows" | quote -}}
{{- end -}}
{{- end -}}

{{/*
Set dbconnector service name
*/}}
{{- define "retool.dbconnector.name" -}}
{{ template "retool.fullname" . }}-dbconnector
{{- end -}}

{{/*
Set workflow backend service name
*/}}
{{- define "retool.workflowBackend.name" -}}
{{ template "retool.fullname" . }}-workflow-backend
{{- end -}}

{{/*
Set workflow worker service name
*/}}
{{- define "retool.workflowWorker.name" -}}
{{ template "retool.fullname" . }}-workflow-worker
{{- end -}}

{{/*
Set code executor service name
*/}}
{{- define "retool.codeExecutor.name" -}}
{{ template "retool.fullname" . }}-code-executor
{{- end -}}

{{/*
Set multiplayer service name
*/}}
{{- define "retool.multiplayer.name" -}}
{{ template "retool.fullname" . }}-multiplayer-ws
{{- end -}}

{{/*
Set agent worker service name
*/}}
{{- define "retool.agentWorker.name" -}}
{{ template "retool.fullname" . }}-agent-worker
{{- end -}}

{{/*
Set agent eval worker service name
*/}}
{{- define "retool.agentEvalWorker.name" -}}
{{ template "retool.fullname" . }}-agent-eval-worker
{{- end -}}

{{/*
Set R2 agent worker service name
*/}}
{{- define "retool.r2AgentWorker.name" -}}
{{ template "retool.fullname" . }}-r2-agent-worker
{{- end -}}

{{/*
Selector labels for R2 agent worker. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.r2AgentWorker.selectorLabels" -}}
retoolService: {{ include "retool.r2AgentWorker.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for R2 agent worker.
*/}}
{{- define "retool.r2AgentWorker.labels" -}}
app.kubernetes.io/name: {{ include "retool.r2AgentWorker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: r2-agent-worker
{{- end }}

{{/*
Set agent executor base name
*/}}
{{- define "retool.agentExecutor.name" -}}
{{ template "retool.fullname" . }}-agent-executor
{{- end -}}

{{/*
Set agent executor controller name
*/}}
{{- define "retool.agentExecutor.controller.name" -}}
{{ template "retool.fullname" . }}-agent-executor-controller
{{- end -}}

{{/*
Set agent executor proxy name
*/}}
{{- define "retool.agentExecutor.proxy.name" -}}
{{ template "retool.fullname" . }}-agent-executor-proxy
{{- end -}}

{{/*
Secret name for agent executor.
Uses externalSecret.name if set, otherwise the auto-generated name.
*/}}
{{- define "retool.agentExecutor.secretName" -}}
{{- if .Values.agentExecutor.externalSecret.name -}}
{{ .Values.agentExecutor.externalSecret.name }}
{{- else -}}
{{ template "retool.agentExecutor.name" . }}
{{- end -}}
{{- end -}}

{{/*
Selector labels for agent executor (executor pods / headless service).
*/}}
{{- define "retool.agentExecutor.selectorLabels" -}}
retoolService: {{ include "retool.agentExecutor.name" . }}
{{- end -}}

{{/*
Extra labels for agent executor.
*/}}
{{- define "retool.agentExecutor.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentExecutor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: agent-executor
{{- end -}}

{{/*
Selector labels for agent executor controller.
*/}}
{{- define "retool.agentExecutor.controller.selectorLabels" -}}
retoolService: {{ include "retool.agentExecutor.controller.name" . }}
{{- end -}}

{{/*
Extra labels for agent executor controller.
*/}}
{{- define "retool.agentExecutor.controller.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentExecutor.controller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: controller
telemetry.retool.com/service-name: agent-executor-controller
{{- end -}}

{{/*
Selector labels for agent executor proxy.
*/}}
{{- define "retool.agentExecutor.proxy.selectorLabels" -}}
retoolService: {{ include "retool.agentExecutor.proxy.name" . }}
{{- end -}}

{{/*
Extra labels for agent executor proxy.
*/}}
{{- define "retool.agentExecutor.proxy.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentExecutor.proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: proxy
telemetry.retool.com/service-name: agent-executor-proxy
{{- end -}}

{{/*
Agent executor env vars for the Retool backend, workflow backend, and workers.
Outputs env entries that tell the backend how to reach the agent executor services.
Usage: {{- include "retool.agentExecutor.backendEnvVars" . | nindent 10 }}
*/}}
{{- define "retool.agentExecutor.backendEnvVars" -}}
{{- if .Values.agentExecutor.enabled }}
- name: AGENT_EXECUTOR_ENABLED
  value: "true"
- name: AGENT_EXECUTOR_CONTROLLER_INGRESS_DOMAIN
  value: {{ .Values.agentExecutor.controllerUrl | default (printf "http://%s:%s" (include "retool.agentExecutor.controller.name" .) (toString .Values.agentExecutor.controller.port)) | quote }}
- name: AGENT_EXECUTOR_PROXY_INGRESS_DOMAIN
  value: {{ .Values.agentExecutor.proxyUrl | default (printf "http://%s:%s" (include "retool.agentExecutor.proxy.name" .) (toString .Values.agentExecutor.proxy.port)) | quote }}
{{- if .Values.agentExecutor.frontendWsProxyDomain }}
- name: AGENT_EXECUTOR_FRONTEND_WS_PROXY_DOMAIN
  value: {{ .Values.agentExecutor.frontendWsProxyDomain | quote }}
{{- end }}
{{- if or .Values.agentExecutor.proxyDomain .Values.agentExecutor.frontendWsProxyDomain }}
- name: AGENT_EXECUTOR_PROXY_DOMAIN
  value: {{ .Values.agentExecutor.proxyDomain | default .Values.agentExecutor.frontendWsProxyDomain | quote }}
{{- end }}
{{- if or .Values.agentExecutor.jwtPrivateKey .Values.agentExecutor.externalSecret.name }}
- name: AGENT_EXECUTOR_JWT_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "retool.agentExecutor.secretName" . }}
      key: jwt-private-key
{{- end }}
{{- if or .Values.agentExecutor.jwtPublicKey .Values.agentExecutor.externalSecret.name }}
- name: AGENT_EXECUTOR_JWT_PUBLIC_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "retool.agentExecutor.secretName" . }}
      key: jwt-public-key
{{- end }}
{{- if or .Values.agentExecutor.encryptionKey .Values.agentExecutor.externalSecret.name }}
- name: AGENT_EXECUTOR_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "retool.agentExecutor.secretName" . }}
      key: encryption-key
{{- end }}
{{- end }}
{{- end -}}

{{/*
Set code executor image tag
Usage: (template "retool.codeExecutor.image.tag" .)
*/}}
{{- define "retool.codeExecutor.image.tag" -}}
{{- if .Values.image.tag -}}
  {{- $valid_retool_version_regexp := "([0-9]+\\.[0-9]+(\\.[0-9]+)?(-[a-zA-Z0-9]+)?)" }}
  {{- $semver_version_regexp := "[0-9]+\\.[0-9]+(\\.[0-9]+)?" }}
  {{- $retool_version_with_ce := ( and ( regexMatch $valid_retool_version_regexp $.Values.image.tag ) ( semverCompare ">= 3.20.15-0" ( regexFind $semver_version_regexp $.Values.image.tag ) ) ) }}
  {{- if $retool_version_with_ce -}}
    {{- .Values.image.tag -}}
  {{- else -}}
    {{- "1.1.0" -}}
  {{- end -}}
{{- else -}}
  {{- fail "Please set a value for .Values.image.tag" }}
{{- end -}}
{{- end -}}

{{- define "retool_version_with_java_dbconnector_opt_out" -}}
{{- $output := "" -}}
{{- $valid_retool_version_regexp := "([0-9]+\\.[0-9]+(\\.[0-9]+)?(-[a-zA-Z0-9]+)?)" }}
{{- $semver_version_regexp := "[0-9]+\\.[0-9]+(\\.[0-9]+)?" }}
{{- if not ( regexMatch $valid_retool_version_regexp .Values.image.tag ) -}}
  {{- $output = "1" -}}
{{- else if semverCompare ">= 3.93.0-0" ( regexFind $semver_version_regexp .Values.image.tag ) -}}
  {{- $output = "1" -}}
{{- else -}}
  {{- $output = "" -}}
{{- end -}}
{{- $output -}}
{{- end -}}

{{/*
Checks whether or not ExternalSecret definitions are enabled and can potentially clobber secrets or explicitly allow additional direct secret refs.
*/}}
{{- define "shouldIncludeConfigSecretsEnvVars" -}}
{{- $output := "" -}}
{{- if or (not (or (.Values.externalSecrets.enabled) (.Values.externalSecrets.externalSecretsOperator.enabled))) .Values.externalSecrets.includeConfigSecrets -}}
  {{- $output = "1" -}}
{{- else -}}
  {{- $output = "" -}}
{{- end -}}
{{- $output -}}
{{- end -}}
