{{/*
Bundled dependencies are selected before templates render. These helpers mirror
Chart.yaml's ordered boolean conditions; do not mutate Values to select them.
Absent canonical controls preserve the legacy configuration exactly.
*/}}
{{- define "retool.database.bundled" -}}
{{- $database := .Values.database | default dict -}}
{{- if hasKey $database "bundled" -}}
{{- $database.bundled -}}
{{- else -}}
{{- .Values.postgresql.enabled -}}
{{- end -}}
{{- end -}}

{{- define "retool.database.external" -}}
{{- $database := .Values.database | default dict -}}
{{- if hasKey $database "external" -}}
{{- $database.external | toYaml -}}
{{- else -}}
{{- .Values.config.postgresql | toYaml -}}
{{- end -}}
{{- end -}}

{{- define "retool.temporal.bundled" -}}
{{- $temporal := .Values.temporal | default dict -}}
{{- if hasKey $temporal "bundled" -}}
{{- $temporal.bundled -}}
{{- else -}}
{{- index .Values "retool-temporal-services-helm" "enabled" -}}
{{- end -}}
{{- end -}}

{{- define "retool.exposure.enabled" -}}
{{- $exposure := .root.Values.exposure | default dict -}}
{{- if $exposure.mode -}}
{{- eq $exposure.mode .mode -}}
{{- else if eq .mode "ingress" -}}
{{- .root.Values.ingress.enabled -}}
{{- else -}}
{{- .root.Values.httpRoute.enabled -}}
{{- end -}}
{{- end -}}

{{- define "retool.configuration.validate" -}}
{{- $database := .Values.database | default dict -}}
{{- $temporal := .Values.temporal | default dict -}}
{{- if and $database.bundled .Values.config.postgresql -}}
{{- fail "database.bundled=true cannot be combined with config.postgresql; remove the legacy external connection settings" -}}
{{- end -}}
{{- if hasKey $database "external" -}}
{{- if eq (include "retool.database.bundled" .) "true" -}}
{{- fail "database.external requires database.bundled=false; set it to disable the bundled PostgreSQL dependency" -}}
{{- end -}}
{{- if .Values.config.postgresql -}}
{{- fail "database.external and config.postgresql cannot be combined; move all connection fields to database.external" -}}
{{- end -}}
{{- $pg := $database.external -}}
{{- if not (and $pg.host $pg.port (or $pg.db $pg.database) $pg.user) -}}
{{- fail "database.external requires host, port, database, and user; provide password or passwordSecretName unless credentials are injected externally" -}}
{{- end -}}
{{- if and (not $pg.password) (not $pg.passwordSecretName) (eq (include "shouldIncludeConfigSecretsEnvVars" . | trim) "1") -}}
{{- fail "database.external requires passwordSecretName (recommended) or password when chart-managed configuration secrets are enabled" -}}
{{- end -}}
{{- end -}}
{{- if and (hasKey $database "bundled") (not $database.bundled) (not (hasKey $database "external")) (not .Values.config.postgresql) -}}
{{- fail "database.bundled=false requires database.external connection settings (or legacy config.postgresql during migration)" -}}
{{- end -}}
{{- if hasKey $temporal "external" -}}
{{- if eq (include "retool.temporal.bundled" .) "true" -}}
{{- fail "temporal.external cannot be combined with temporal.bundled=true; select one Temporal cluster" -}}
{{- end -}}
{{- if or .Values.workflows.temporal $temporal.enabled $temporal.host $temporal.port $temporal.namespace $temporal.sslEnabled $temporal.sslCert $temporal.sslKey $temporal.sslKeySecretName $temporal.sslKeySecretKey -}}
{{- fail "temporal.external cannot be combined with legacy temporal connection settings or workflows.temporal; move all connection fields to temporal.external" -}}
{{- end -}}
{{- if not (and $temporal.external.host $temporal.external.port $temporal.external.namespace) -}}
{{- fail "temporal.external requires host, port, and namespace" -}}
{{- end -}}
{{- end -}}
{{- if and $temporal.bundled (or $temporal.enabled (.Values.workflows.temporal).enabled) -}}
{{- fail "temporal.bundled=true cannot be combined with an enabled external Temporal cluster; remove the legacy external settings" -}}
{{- end -}}
{{- end -}}
