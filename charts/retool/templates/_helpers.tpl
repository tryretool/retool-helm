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
Whether MCP routing needs the main Retool Service to expose the backend API
listener in addition to the primary frontend-facing port.
*/}}
{{- define "retool.mcp.needsBackendApi" -}}
{{- $mcp := .Values.mcp | default dict -}}
{{- $mcpIngress := $mcp.ingress | default dict -}}
{{- $mcpHttpRoute := $mcp.httpRoute | default dict -}}
{{- $needsBackendApi := false -}}
{{- if and .Values.ingress.enabled $mcp.enabled $mcpIngress.enabled -}}
{{- range ($mcpIngress.paths | default list) -}}
{{- if eq (.target | default "mcp") "backendApi" -}}
{{- $needsBackendApi = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .Values.httpRoute.enabled $mcp.enabled $mcpHttpRoute.enabled -}}
{{- range ($mcpHttpRoute.rules | default list) -}}
{{- if eq (.target | default "mcp") "backendApi" -}}
{{- $needsBackendApi = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $needsBackendApi -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Render an MCP-related Ingress path. By default paths route to the MCP service;
target: backendApi routes to the main backend API listener instead.
*/}}
{{- define "retool.ingress.mcpPath" -}}
{{- $root := .root -}}
{{- $path := .path -}}
{{- $target := .target | default ($path.target | default "mcp") -}}
{{- if not (or (eq $target "mcp") (eq $target "backendApi")) -}}
{{- fail (printf "Invalid mcp.ingress.paths target %q for path %q. Valid targets are \"mcp\" and \"backendApi\"." $target $path.path) -}}
{{- end -}}
{{- $mcpService := (($root.Values.mcp).service) | default dict -}}
{{- $serviceName := include "retool.mcp.name" $root -}}
{{- $servicePort := $path.port | default ($mcpService.externalPort | default 4010) -}}
{{- $pathType := $path.pathType | default "ImplementationSpecific" -}}
{{- if eq $target "backendApi" -}}
{{- $serviceName = include "retool.fullname" $root -}}
{{- $servicePort = $path.port | default (.backendApiPort | default 3001) -}}
{{- $pathType = $path.pathType | default "Exact" -}}
{{- end -}}
- path: {{ $path.path }}
  {{- if (semverCompare ">=1.18-0" $root.Capabilities.KubeVersion.Version) }}
  pathType: {{ $pathType }}
  {{- end }}
  backend:
    {{- if semverCompare ">=1.19-0" $root.Capabilities.KubeVersion.Version }}
    service:
      name: {{ $serviceName }}
      port:
        number: {{ $servicePort }}
    {{- else }}
    serviceName: {{ $serviceName }}
    servicePort: {{ $servicePort }}
    {{- end }}
{{- end }}

{{/*
Render an MCP-related HTTPRoute rule. By default rules route to the MCP service;
target: backendApi routes to the main backend API listener instead.
*/}}
{{- define "retool.httpRoute.mcpRule" -}}
{{- $root := .root -}}
{{- $rule := .rule -}}
{{- $target := .target | default ($rule.target | default "mcp") -}}
{{- if not (or (eq $target "mcp") (eq $target "backendApi")) -}}
{{- fail (printf "Invalid mcp.httpRoute.rules target %q for path %q. Valid targets are \"mcp\" and \"backendApi\"." $target $rule.path) -}}
{{- end -}}
{{- $mcpService := (($root.Values.mcp).service) | default dict -}}
{{- $serviceName := include "retool.mcp.name" $root -}}
{{- $servicePort := $rule.port | default ($mcpService.externalPort | default 4010) -}}
{{- $pathType := $rule.pathType | default "PathPrefix" -}}
{{- if eq $target "backendApi" -}}
{{- $serviceName = include "retool.fullname" $root -}}
{{- $servicePort = $rule.port | default (.backendApiPort | default 3001) -}}
{{- $pathType = $rule.pathType | default "Exact" -}}
{{- end -}}
- matches:
    - path:
        type: {{ $pathType }}
        value: {{ $rule.path }}
  backendRefs:
    - name: {{ $serviceName }}
      port: {{ $servicePort }}
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
Selector labels for js executor. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.jsExecutor.selectorLabels" -}}
retoolService: {{ include "retool.jsExecutor.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for js executor.
*/}}
{{- define "retool.jsExecutor.labels" -}}
app.kubernetes.io/name: {{ include "retool.jsExecutor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: js-executor
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

{{/*
Render map-style env values as Kubernetes EnvVar entries.
Scalar values are always quoted so YAML booleans and numbers become strings.
Map values allow structured EnvVar fields such as valueFrom.
*/}}
{{- define "retool.env" -}}
{{- range $key, $value := . }}
- name: {{ $key | quote }}
{{- if kindIs "map" $value }}
{{- if hasKey $value "value" }}
  value: {{ get $value "value" | quote }}
{{- end }}
{{- range $field, $fieldValue := omit $value "value" }}
  {{ $field }}:
{{ toYaml $fieldValue | indent 4 }}
{{- end }}
{{- else }}
  value: {{ $value | quote }}
{{- end }}
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
Set JS executor service name
*/}}
{{- define "retool.jsExecutor.name" -}}
{{ template "retool.fullname" . }}-js-executor
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
Set agent sandbox base name
*/}}
{{- define "retool.agentSandbox.name" -}}
{{ template "retool.fullname" . }}-agent-sandbox
{{- end -}}

{{/*
Set agent sandbox controller name
*/}}
{{- define "retool.agentSandbox.controller.name" -}}
{{ template "retool.fullname" . }}-agent-sandbox-controller
{{- end -}}

{{/*
Set agent sandbox proxy name
*/}}
{{- define "retool.agentSandbox.proxy.name" -}}
{{ template "retool.fullname" . }}-agent-sandbox-proxy
{{- end -}}

{{/*
Selector labels for agent sandbox (sandbox pods / headless service).
*/}}
{{- define "retool.agentSandbox.selectorLabels" -}}
retoolService: {{ include "retool.agentSandbox.name" . }}
{{- end -}}

{{/*
Extra labels for agent sandbox.
*/}}
{{- define "retool.agentSandbox.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentSandbox.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
telemetry.retool.com/service-name: agent-sandbox
{{- end -}}

{{/*
Selector labels for agent sandbox controller.
*/}}
{{- define "retool.agentSandbox.controller.selectorLabels" -}}
retoolService: {{ include "retool.agentSandbox.controller.name" . }}
{{- end -}}

{{/*
Extra labels for agent sandbox controller.
*/}}
{{- define "retool.agentSandbox.controller.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentSandbox.controller.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: controller
telemetry.retool.com/service-name: agent-sandbox-controller
{{- end -}}

{{/*
Selector labels for agent sandbox proxy.
*/}}
{{- define "retool.agentSandbox.proxy.selectorLabels" -}}
retoolService: {{ include "retool.agentSandbox.proxy.name" . }}
{{- end -}}

{{/*
Extra labels for agent sandbox proxy.
*/}}
{{- define "retool.agentSandbox.proxy.labels" -}}
app.kubernetes.io/name: {{ include "retool.agentSandbox.proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: proxy
telemetry.retool.com/service-name: agent-sandbox-proxy
{{- end -}}

{{/*
Agent sandbox env vars for the Retool backend, workflow backend, and workers.
Outputs env entries that tell the backend how to reach the agent sandbox services.
Usage: {{- include "retool.agentSandbox.backendEnvVars" . | nindent 10 }}
*/}}
{{- define "retool.agentSandbox.backendEnvVars" -}}
{{- if .Values.agentSandbox.enabled }}
{{- $defaultSecretName := .Values.agentSandbox.externalSecret.name | default (include "retool.agentSandbox.name" .) -}}
- name: RR_AGENT_PUBSUB_BACKEND
  value: "postgres"
- name: AGENT_SANDBOX_CONTROLLER_INGRESS_DOMAIN
  value: {{ .Values.agentSandbox.controllerUrl | default (printf "http://%s:%s" (include "retool.agentSandbox.controller.name" .) (toString .Values.agentSandbox.controller.port)) | quote }}
- name: AGENT_SANDBOX_PROXY_INGRESS_DOMAIN
  value: {{ .Values.agentSandbox.proxyUrl | default (printf "http://%s:%s" (include "retool.agentSandbox.proxy.name" .) (toString .Values.agentSandbox.proxy.port)) | quote }}
{{- if .Values.agentSandbox.frontendWsProxyDomain }}
- name: AGENT_SANDBOX_FRONTEND_WS_PROXY_DOMAIN
  value: {{ .Values.agentSandbox.frontendWsProxyDomain | quote }}
{{- end }}
{{- if .Values.agentSandbox.jwtPrivateKey }}
- name: AGENT_SANDBOX_JWT_PRIVATE_KEY
  value: {{ .Values.agentSandbox.jwtPrivateKey | quote }}
{{- else if .Values.agentSandbox.externalSecret.name }}
- name: AGENT_SANDBOX_JWT_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $defaultSecretName }}
      key: jwt-private-key
{{- end }}
{{- if .Values.agentSandbox.jwtPublicKey }}
- name: AGENT_SANDBOX_JWT_PUBLIC_KEY
  value: {{ .Values.agentSandbox.jwtPublicKey | quote }}
{{- else if .Values.agentSandbox.externalSecret.name }}
- name: AGENT_SANDBOX_JWT_PUBLIC_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $defaultSecretName }}
      key: jwt-public-key
{{- end }}
{{- if .Values.agentSandbox.encryptionKey }}
- name: AGENT_SANDBOX_ENCRYPTION_KEY
  value: {{ .Values.agentSandbox.encryptionKey | quote }}
{{- else if .Values.agentSandbox.externalSecret.name }}
- name: AGENT_SANDBOX_ENCRYPTION_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $defaultSecretName }}
      key: encryption-key
{{- end }}
{{- end }}
{{- end -}}

{{/*
Set MCP server service name
*/}}
{{- define "retool.mcp.name" -}}
{{ template "retool.fullname" . }}-mcp
{{- end -}}

{{/*
Validate that exactly one blob-storage provider is configured when rrGitServer
is enabled. Skipped when the user has plumbed the RR_BLOB_STORAGE_PROVIDER /
RR_DEFAULT_*_* env vars in directly via env/environmentVariables/environmentSecrets,
which is treated as an opt-out from the first-class blobStorage config.
No-op when rrGitServer is disabled.
*/}}
{{- define "retool.rrGitServer.validateBlobStorage" -}}
{{- if .Values.rrGitServer.enabled -}}
{{- $hasDirectEnv := false -}}
{{- range $name, $value := .Values.env -}}
{{- if or (hasPrefix "RR_DEFAULT_" $name) (eq $name "RR_BLOB_STORAGE_PROVIDER") -}}
{{- $hasDirectEnv = true -}}
{{- end -}}
{{- end -}}
{{- range .Values.environmentVariables -}}
{{- if or (hasPrefix "RR_DEFAULT_" .name) (eq .name "RR_BLOB_STORAGE_PROVIDER") -}}
{{- $hasDirectEnv = true -}}
{{- end -}}
{{- end -}}
{{- range .Values.environmentSecrets -}}
{{- if or (hasPrefix "RR_DEFAULT_" .name) (eq .name "RR_BLOB_STORAGE_PROVIDER") -}}
{{- $hasDirectEnv = true -}}
{{- end -}}
{{- end -}}
{{- if not $hasDirectEnv -}}
{{- $bs := .Values.blobStorage | default dict -}}
{{- $providers := list -}}
{{- if $bs.s3 }}{{ $providers = append $providers "s3" }}{{ end -}}
{{- if $bs.gcs }}{{ $providers = append $providers "gcs" }}{{ end -}}
{{- if $bs.azure }}{{ $providers = append $providers "azure" }}{{ end -}}
{{- if ne (len $providers) 1 -}}
{{- fail "rrGitServer.enabled requires exactly one of blobStorage.s3, blobStorage.gcs, blobStorage.azure to be configured, or set RR_BLOB_STORAGE_PROVIDER / RR_DEFAULT_* directly via env / environmentVariables / environmentSecrets" -}}
{{- end -}}
{{- end -}}
{{- end -}}
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

{{/*
Set JS executor image tag
Usage: (template "retool.jsExecutor.image.tag" .)
*/}}
{{- define "retool.jsExecutor.image.tag" -}}
{{- if .Values.jsExecutor.image.tag -}}
  {{- .Values.jsExecutor.image.tag -}}
{{- else if .Values.image.tag -}}
  {{- $valid_retool_version_regexp := "([0-9]+\\.[0-9]+(\\.[0-9]+)?(-[a-zA-Z0-9]+)?)" }}
  {{- $semver_version_regexp := "[0-9]+\\.[0-9]+(\\.[0-9]+)?" }}
  {{- $retool_version_with_ce := ( and ( regexMatch $valid_retool_version_regexp $.Values.image.tag ) ( semverCompare ">= 3.20.15-0" ( regexFind $semver_version_regexp $.Values.image.tag ) ) ) }}
  {{- if $retool_version_with_ce -}}
    {{- .Values.image.tag -}}
  {{- else -}}
    {{- "1.1.0" -}}
  {{- end -}}
{{- else -}}
  {{- fail "Please set a value for .Values.image.tag or .Values.jsExecutor.image.tag" }}
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
