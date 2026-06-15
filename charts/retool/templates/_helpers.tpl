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
Resolve whether an RR component (agent, jsExecutor, agentSandbox) is
enabled. Components are nested under .Values.rr (each ships as a default block
with `enabled: null`). The component's own `enabled` wins when explicitly set to
true/false; when left unset (null) it inherits the shared master switch
.Values.rr.enabled. If the component block itself is absent or explicitly nulled
it is treated as disabled (there is no config to render). A non-mapping value
(e.g. a bare bool) is a misconfiguration and fails loudly.
Usage: (include "retool.rr.componentEnabled" (dict "root" $ "component" "jsExecutor"))
Returns "1" when enabled, "" otherwise.
*/}}
{{- define "retool.rr.componentEnabled" -}}
{{- $rr := .root.Values.rr | default dict -}}
{{- $cfg := index $rr .component -}}
{{- if kindIs "invalid" $cfg -}}
  {{/* component block absent or explicitly nulled -> disabled (there is no
       config to render, so it cannot inherit the master switch on) */}}
{{- else if kindIs "map" $cfg -}}
  {{- if kindIs "invalid" $cfg.enabled -}}
    {{- if eq (toString $rr.enabled) "true" -}}1{{- end -}}
  {{- else if eq (toString $cfg.enabled) "true" -}}1{{- end -}}
{{- else -}}
  {{- fail (printf "rr.%s must be a mapping (got %s). To toggle this component set rr.%s.enabled: true|false; to inherit the rr.enabled master switch, leave rr.%s unset." .component (kindOf $cfg) .component .component) -}}
{{- end -}}
{{- end -}}

{{/*
Set RR agent worker enabled. Honors the shared RR master switch.
Usage: (include "retool.agent.enabled" .)
*/}}
{{- define "retool.agent.enabled" -}}
{{- include "retool.rr.componentEnabled" (dict "root" . "component" "agent") -}}
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
Set RR agent worker service name
*/}}
{{- define "retool.rrAgentWorker.name" -}}
{{ template "retool.fullname" . }}-r2-agent-worker
{{- end -}}

{{/*
Selector labels for RR agent worker. Note changes here will require manual
deployment recreation and incur downtime, so should be avoided.
*/}}
{{- define "retool.rrAgentWorker.selectorLabels" -}}
retoolService: {{ include "retool.rrAgentWorker.name" . }}
{{- end }}

{{/*
Extra (non-selector) labels for RR agent worker.
*/}}
{{- define "retool.rrAgentWorker.labels" -}}
app.kubernetes.io/name: {{ include "retool.rrAgentWorker.name" . }}
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
Internal URL for server-side callers to reach the agent sandbox proxy Service.
The fully-qualified cluster DNS name keeps this default valid even when callers
run outside the proxy Service's namespace.
*/}}
{{- define "retool.agentSandbox.proxyUrl" -}}
{{- .Values.rr.agentSandbox.proxyUrl | default (printf "http://%s.%s.svc.cluster.local:%s" (include "retool.agentSandbox.proxy.name" .) .Release.Namespace (toString .Values.rr.agentSandbox.proxy.port)) -}}
{{- end -}}

{{/*
Agent sandbox proxy env var for server-side callers. Keep this separate from
AGENT_*_FRONTEND_WS_PROXY_DOMAIN, which is browser-facing public config.
*/}}
{{- define "retool.agentSandbox.proxyEnvVars" -}}
{{- if eq (include "retool.rr.componentEnabled" (dict "root" . "component" "agentSandbox")) "1" }}
- name: AGENT_SANDBOX_PROXY_INGRESS_DOMAIN
  value: {{ include "retool.agentSandbox.proxyUrl" . | quote }}
{{- end }}
{{- end -}}

{{/*
Validate that an enabled agent sandbox has its required secrets supplied. The
controller and proxy fail to boot without a Postgres connection and a JWT
public key, and the Retool backend needs the JWT private key to sign sandbox
tokens. Each may come from a plaintext value, the per-key existing-secret refs,
or the catch-all externalSecret.name. No-op when agentSandbox is disabled.
*/}}
{{- define "retool.agentSandbox.validateSecrets" -}}
{{- if eq (include "retool.rr.componentEnabled" (dict "root" . "component" "agentSandbox")) "1" -}}
{{- $as := .Values.rr.agentSandbox -}}
{{- $ext := $as.externalSecret.name -}}
{{- $explicitPg := or $as.postgres.url $as.postgres.urlSecretName $as.postgres.host -}}
{{- if not $explicitPg -}}
{{- /* No explicit source: inherit the backend's Postgres connection. */ -}}
{{- if not (include "retool.postgresql.host" . | trimAll "\"") -}}
{{- fail "agentSandbox.enabled defaults to reusing the backend's Postgres connection, but config.postgresql resolved no host. Set agentSandbox.postgres.url / .host / .urlSecretName (point .urlSecretName at your externalSecret to reuse its postgres-url key; externalSecret.name alone only covers the JWT/encryption keys), or configure config.postgresql." -}}
{{- end -}}
{{- if not (or .Values.postgresql.enabled .Values.config.postgresql.passwordSecretName (eq (include "shouldIncludeConfigSecretsEnvVars" . | trim) "1")) -}}
{{- fail "agentSandbox.postgres is unset so it would inherit the backend's Postgres password, but that password is supplied via external secrets (envFrom) and cannot be referenced from a separate pod. Set agentSandbox.postgres.url / .urlSecretName / .host (+ passwordSecretName) -- .urlSecretName can point at your externalSecret's postgres-url key (externalSecret.name alone only covers the JWT/encryption keys)." -}}
{{- end -}}
{{- end -}}
{{- if $as.postgres.host -}}
{{- if not (and $as.postgres.user $as.postgres.database) -}}
{{- fail "agentSandbox.postgres.host is set, so postgres.user and postgres.database are also required to assemble the DSN." -}}
{{- end -}}
{{- if not (or $as.postgres.password $as.postgres.passwordSecretName) -}}
{{- fail "agentSandbox.postgres.host is set, so a password is required: set postgres.password or postgres.passwordSecretName. For a passwordless connection (e.g. IAM/trust auth), supply the full connection string via postgres.url or postgres.urlSecretName instead." -}}
{{- end -}}
{{- /*
  user and database are embedded verbatim in the assembled DSN, so reject the
  characters that would break URL parsing. '@' is allowed in user (managed
  services like Azure use user@servername; the parser splits on the last '@'),
  but ':' '/' and whitespace would be mis-parsed as a password/host/path. For
  values needing other characters, supply a full DSN via postgres.url or
  postgres.urlSecretName instead.
*/}}
{{- if regexMatch "[\\s:/?#]" ($as.postgres.user | toString) -}}
{{- fail "agentSandbox.postgres.user contains a character that breaks DSN assembly (whitespace, : / ? #). '@' is fine (e.g. Azure user@server); otherwise supply a full DSN via agentSandbox.postgres.url or postgres.urlSecretName." -}}
{{- end -}}
{{- if regexMatch "[\\s:/?#]" ($as.postgres.database | toString) -}}
{{- fail "agentSandbox.postgres.database contains a character that breaks DSN assembly (whitespace, : / ? #); supply a full DSN via agentSandbox.postgres.url or postgres.urlSecretName." -}}
{{- end -}}
{{- end -}}
{{- if not (or $as.jwtPublicKey $ext) -}}
{{- fail "agentSandbox.enabled requires a JWT public key. Set agentSandbox.jwtPublicKey or agentSandbox.externalSecret.name." -}}
{{- end -}}
{{- if not (or $as.jwtPrivateKey $ext) -}}
{{- fail "agentSandbox.enabled requires a JWT private key (the backend signs sandbox tokens with it). Set agentSandbox.jwtPrivateKey or agentSandbox.externalSecret.name." -}}
{{- end -}}
{{- if not (or $as.encryptionKey $ext) -}}
{{- fail "agentSandbox.enabled requires an encryption key: the proxy derives the sandbox-iframe asset-token HMAC key from it and throws when serving a sandbox without it, and the backend must use the same value. Set agentSandbox.encryptionKey (64 hex chars, openssl rand -hex 32) or agentSandbox.externalSecret.name (with an encryption-key entry)." -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Render the AGENT_SANDBOX_POSTGRES_URL env entry for the controller/proxy (plus a
PGPASSWORD entry when assembling from fields). validateSecrets guarantees one of
these applies, in order: postgres.url -> postgres.host -> postgres.urlSecretName
-> inherit the backend's config.postgresql connection (the default when nothing
agent-specific is set). externalSecret.name covers only the JWT/encryption keys
-- it never sources Postgres. To read a DSN from that same secret, point
postgres.urlSecretName at it (its postgres-url key is the urlSecretKey default).

For the host path the password is passed via PGPASSWORD rather than embedded in
the URL: node-postgres reads PGPASSWORD when the connection string omits the
password, so it needs no URL escaping. PGPASSWORD is process-global but safe
here because the controller/proxy open exactly one Postgres connection. user and
database are embedded verbatim (percent-encoding doesn't round-trip here -- the
parser decodes userinfo before splitting on ':', and runs the path through
decodeURI); validateSecrets instead rejects the characters that would break
parsing. An Azure-style "user@servername" is fine -- the parser splits on the
last '@'.
Usage: {{- include "retool.agentSandbox.postgresUrlEnv" . | nindent 12 }}
*/}}
{{- define "retool.agentSandbox.postgresUrlEnv" -}}
{{- $pg := .Values.rr.agentSandbox.postgres -}}
{{- if $pg.url }}
- name: AGENT_SANDBOX_POSTGRES_URL
  value: {{ $pg.url | quote }}
{{- else if $pg.host }}
{{- $port := $pg.port | default 5432 -}}
{{- if $pg.passwordSecretName }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $pg.passwordSecretName }}
      key: {{ $pg.passwordSecretKey | default "password" }}
{{- else if $pg.password }}
- name: PGPASSWORD
  value: {{ $pg.password | quote }}
{{- end }}
- name: AGENT_SANDBOX_POSTGRES_URL
  value: {{ printf "postgres://%s@%s:%v/%s" $pg.user $pg.host $port $pg.database | quote }}
{{- else if $pg.urlSecretName }}
- name: AGENT_SANDBOX_POSTGRES_URL
  valueFrom:
    secretKeyRef:
      name: {{ $pg.urlSecretName }}
      key: {{ $pg.urlSecretKey | default "postgres-url" }}
{{- /*
  The DSN may omit the password; supply it separately via passwordSecretName so
  an auto-rotated password (e.g. the backend's RDS secret) isn't duplicated into
  the DSN secret. node-postgres reads PGPASSWORD when the URL omits the password.
*/}}
{{- if $pg.passwordSecretName }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $pg.passwordSecretName }}
      key: {{ $pg.passwordSecretKey | default "password" }}
{{- end }}
{{- else }}
{{- /*
  Default: inherit the backend's Postgres connection (config.postgresql or the
  postgresql subchart) -- same instance/database, separate schema. The password
  is sourced from the same secret the backend uses; this block mirrors the
  POSTGRES_PASSWORD secretKeyRef in deployment_backend.yaml. validateSecrets
  rejects the one combination this can't reach (external-secrets mode with no
  discrete password key).
*/}}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      {{- if .Values.postgresql.enabled }}
      name: {{ template "retool.postgresql.fullname" . }}
      {{- if eq .Values.postgresql.auth.username "postgres" }}
      key: postgres-password
      {{- else }}
      key: password
      {{- end }}
      {{- else if .Values.config.postgresql.passwordSecretName }}
      name: {{ .Values.config.postgresql.passwordSecretName }}
      key: {{ .Values.config.postgresql.passwordSecretKey | default "postgresql-password" }}
      {{- else }}
      name: {{ template "retool.fullname" . }}
      key: postgresql-password
      {{- end }}
- name: AGENT_SANDBOX_POSTGRES_URL
  value: {{ printf "postgres://%s@%s:%s/%s" (include "retool.postgresql.user" . | trimAll "\"") (include "retool.postgresql.host" . | trimAll "\"") (include "retool.postgresql.port" . | trimAll "\"" | default "5432") (include "retool.postgresql.database" . | trimAll "\"") | quote }}
{{- end }}
{{- end -}}

{{/*
Agent sandbox env vars for the Retool backend, workflow backend, and workers.
Outputs env entries that tell the backend how to reach the agent sandbox services.
Usage: {{- include "retool.agentSandbox.backendEnvVars" . | nindent 10 }}
*/}}
{{- define "retool.agentSandbox.backendEnvVars" -}}
{{- if eq (include "retool.rr.componentEnabled" (dict "root" . "component" "agentSandbox")) "1" }}
{{- $defaultSecretName := .Values.rr.agentSandbox.externalSecret.name | default (include "retool.agentSandbox.name" .) -}}
- name: RR_AGENT_PUBSUB_BACKEND
  value: "postgres"
- name: AGENT_SANDBOX_CONTROLLER_INGRESS_DOMAIN
  value: {{ .Values.rr.agentSandbox.controllerUrl | default (printf "http://%s:%s" (include "retool.agentSandbox.controller.name" .) (toString .Values.rr.agentSandbox.controller.port)) | quote }}
{{- include "retool.agentSandbox.proxyEnvVars" . }}
{{- if .Values.rr.agentSandbox.frontendWsProxyDomain }}
- name: AGENT_SANDBOX_FRONTEND_WS_PROXY_DOMAIN
  value: {{ .Values.rr.agentSandbox.frontendWsProxyDomain | quote }}
{{- end }}
{{- if .Values.rr.agentSandbox.jwtPrivateKey }}
- name: AGENT_SANDBOX_JWT_PRIVATE_KEY
  value: {{ .Values.rr.agentSandbox.jwtPrivateKey | quote }}
{{- else if .Values.rr.agentSandbox.externalSecret.name }}
- name: AGENT_SANDBOX_JWT_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $defaultSecretName }}
      key: jwt-private-key
{{- end }}
{{- if .Values.rr.agentSandbox.jwtPublicKey }}
- name: AGENT_SANDBOX_JWT_PUBLIC_KEY
  value: {{ .Values.rr.agentSandbox.jwtPublicKey | quote }}
{{- else if .Values.rr.agentSandbox.externalSecret.name }}
- name: AGENT_SANDBOX_JWT_PUBLIC_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $defaultSecretName }}
      key: jwt-public-key
{{- end }}
{{- if .Values.rr.agentSandbox.encryptionKey }}
- name: AGENT_SANDBOX_ENCRYPTION_KEY
  value: {{ .Values.rr.agentSandbox.encryptionKey | quote }}
{{- else if .Values.rr.agentSandbox.externalSecret.name }}
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
Set git server deployment/service name (only used when rr.gitServer.separate is enabled)
*/}}
{{- define "retool.gitServer.name" -}}
{{ template "retool.fullname" . }}-git-server
{{- end -}}

{{/*
Returns "1" when the git server should run as its own deployment/service
(rr.gitServer.enabled AND rr.gitServer.separate.enabled), empty otherwise.
*/}}
{{- define "retool.gitServer.separateEnabled" -}}
{{- if and .Values.rr.gitServer.enabled (.Values.rr.gitServer.separate | default dict).enabled -}}
1
{{- end -}}
{{- end -}}

{{/*
Port the standalone git server listens on (RR_GIT_SERVER_PORT) and exposes via its service.
*/}}
{{- define "retool.gitServer.port" -}}
{{- (.Values.rr.gitServer.separate | default dict).port | default 3010 -}}
{{- end -}}

{{/*
In-cluster URL of the standalone git server service, e.g. http://<release>-git-server:3010.
Used to point the MCP server (and any other consumer) at the split-out git server.
*/}}
{{- define "retool.gitServer.url" -}}
http://{{ template "retool.gitServer.name" . }}:{{ include "retool.gitServer.port" . }}
{{- end -}}

{{/*
Blob-storage + git repack env vars shared by the in-process git server (main
backend) and the standalone git server deployment. git_server stores all
objects/packs in blob storage; the same RR_DEFAULT_* vars are also used by
snapshots. Emits nothing when no blobStorage provider is configured (in which
case the user is expected to plumb RR_BLOB_STORAGE_PROVIDER / RR_DEFAULT_*
directly via environmentVariables / environmentSecrets).
*/}}
{{- define "retool.gitServer.commonEnv" -}}
{{- $bs := .Values.rr.blobStorage | default dict }}
{{- if $bs.s3 }}
- name: RR_BLOB_STORAGE_PROVIDER
  value: "s3"
- name: RR_DEFAULT_S3_BUCKET
  value: {{ $bs.s3.bucket | quote }}
{{- if $bs.s3.region }}
- name: RR_DEFAULT_S3_REGION
  value: {{ $bs.s3.region | quote }}
{{- end }}
{{- if $bs.s3.endpoint }}
- name: RR_DEFAULT_S3_ENDPOINT
  value: {{ $bs.s3.endpoint | quote }}
{{- end }}
{{- if $bs.s3.accessKeyId }}
- name: RR_DEFAULT_S3_ACCESS_KEY_ID
  value: {{ $bs.s3.accessKeyId | quote }}
{{- end }}
{{- if $bs.s3.secretAccessKeySecretName }}
- name: RR_DEFAULT_S3_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $bs.s3.secretAccessKeySecretName }}
      key: {{ $bs.s3.secretAccessKeySecretKey | default "secret-access-key" }}
{{- else if $bs.s3.secretAccessKey }}
- name: RR_DEFAULT_S3_SECRET_ACCESS_KEY
  value: {{ $bs.s3.secretAccessKey | quote }}
{{- end }}
{{- else if $bs.gcs }}
- name: RR_BLOB_STORAGE_PROVIDER
  value: "gcs"
- name: RR_DEFAULT_GCS_BUCKET
  value: {{ $bs.gcs.bucket | quote }}
{{- if $bs.gcs.credentialsSecretName }}
- name: RR_DEFAULT_GCS_CREDENTIALS
  valueFrom:
    secretKeyRef:
      name: {{ $bs.gcs.credentialsSecretName }}
      key: {{ $bs.gcs.credentialsSecretKey | default "credentials.json" }}
{{- else if $bs.gcs.credentials }}
- name: RR_DEFAULT_GCS_CREDENTIALS
  value: {{ $bs.gcs.credentials | quote }}
{{- end }}
{{- else if $bs.azure }}
- name: RR_BLOB_STORAGE_PROVIDER
  value: "azure"
- name: RR_DEFAULT_AZURE_CONTAINER
  value: {{ $bs.azure.container | quote }}
{{- if $bs.azure.connectionStringSecretName }}
- name: RR_DEFAULT_AZURE_CONNECTION_STRING
  valueFrom:
    secretKeyRef:
      name: {{ $bs.azure.connectionStringSecretName }}
      key: {{ $bs.azure.connectionStringSecretKey | default "connection-string" }}
{{- else if $bs.azure.connectionString }}
- name: RR_DEFAULT_AZURE_CONNECTION_STRING
  value: {{ $bs.azure.connectionString | quote }}
{{- end }}
{{- end }}
{{- if .Values.rr.gitServer.repackThreshold }}
- name: RR_GIT_REPACK_THRESHOLD
  value: {{ .Values.rr.gitServer.repackThreshold | quote }}
{{- end }}
{{- end -}}

{{/*
Validate that exactly one blob-storage provider is configured when rr.gitServer
is enabled. Skipped when the user has plumbed the RR_BLOB_STORAGE_PROVIDER /
RR_DEFAULT_*_* env vars in directly via env/environmentVariables/environmentSecrets,
which is treated as an opt-out from the first-class blobStorage config.
Also skipped entirely when rr.gitServer.skipBlobStorageValidation is true, which
is the escape hatch for sources we cannot inspect at template time (e.g. env
vars injected via envFrom from a Secret/ConfigMap).
No-op when rr.gitServer is disabled.
*/}}
{{- define "retool.gitServer.validateBlobStorage" -}}
{{- if and .Values.rr.gitServer.enabled (not .Values.rr.gitServer.skipBlobStorageValidation) -}}
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
{{- $bs := .Values.rr.blobStorage | default dict -}}
{{- $providers := list -}}
{{- if $bs.s3 }}{{ $providers = append $providers "s3" }}{{ end -}}
{{- if $bs.gcs }}{{ $providers = append $providers "gcs" }}{{ end -}}
{{- if $bs.azure }}{{ $providers = append $providers "azure" }}{{ end -}}
{{- if ne (len $providers) 1 -}}
{{- fail "rr.gitServer.enabled requires exactly one of rr.blobStorage.s3, rr.blobStorage.gcs, rr.blobStorage.azure to be configured, or set RR_BLOB_STORAGE_PROVIDER / RR_DEFAULT_* directly via env / environmentVariables / environmentSecrets. If those vars are supplied another way (e.g. envFrom), set rr.gitServer.skipBlobStorageValidation=true to bypass this check." -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Guard against the pre-rename RR values layout. The whole stack used to be named
"r2" (top-level `r2:` master switch), and its components used to be top-level
keys (jsExecutor, r2Agent, agentSandbox, rrGitServer, blobStorage); everything is
now named "rr" and nested under .Values.rr. A chart upgrade would otherwise
SILENTLY ignore any config still set under the old names — quietly disabling RR —
so fail loudly with the exact key moves instead.

Two classes of stale config are caught:
  1. Old TOP-LEVEL keys (the master switch and the un-nested components).
  2. Old component LEAF names nested under the new `rr:` block (e.g. someone
     who moved config under `rr:` but kept `r2Agent`/`rrAgent`/`rrGitServer`/
     `rrBlobStorage` instead of the renamed `agent`/`gitServer`/`blobStorage`).
*/}}
{{- define "retool.rr.validateLegacyValues" -}}
{{- $found := list -}}
{{/* 1. old top-level keys */}}
{{- $topMoves := list
  (list "r2"           "rr")
  (list "jsExecutor"   "rr.jsExecutor")
  (list "r2Agent"      "rr.agent")
  (list "agentSandbox" "rr.agentSandbox")
  (list "rrGitServer"  "rr.gitServer")
  (list "blobStorage"  "rr.blobStorage") -}}
{{- range $move := $topMoves -}}
{{- if hasKey $.Values (index $move 0) -}}
{{- $found = append $found (printf "  %s:  ->  %s:" (index $move 0) (index $move 1)) -}}
{{- end -}}
{{- end -}}
{{/* 2. old leaf names nested under rr: */}}
{{- $rr := $.Values.rr | default dict -}}
{{- $childMoves := list
  (list "r2Agent"       "rr.agent")
  (list "rrAgent"       "rr.agent")
  (list "rrGitServer"   "rr.gitServer")
  (list "rrBlobStorage" "rr.blobStorage") -}}
{{- range $move := $childMoves -}}
{{- if hasKey $rr (index $move 0) -}}
{{- $found = append $found (printf "  rr.%s:  ->  %s:" (index $move 0) (index $move 1)) -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
{{- fail (printf "\n\nACTION REQUIRED: update your Helm values file.\n\nThe RR (formerly \"r2\") values layout changed: the master switch and every component it needs now live under the top-level `rr:` block. The keys below are still set in your values but are NO LONGER READ, which would silently disable RR. This deploy is blocked until you fix it.\n\nTo fix: edit your values file (values.yaml / your Helm values overrides) and rename / move these keys:\n\n%s\n\nThe master switch is now `rr.enabled`. See the chart's values.yaml for the full new layout." (join "\n" $found)) -}}
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
{{- if .Values.rr.jsExecutor.image.tag -}}
  {{- .Values.rr.jsExecutor.image.tag -}}
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
  {{- fail "Please set a value for .Values.image.tag or .Values.rr.jsExecutor.image.tag" }}
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
