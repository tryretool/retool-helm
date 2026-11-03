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

{{- define "retool.configuration.validate" -}}
{{- $database := .Values.database | default dict -}}
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
{{- end -}}
