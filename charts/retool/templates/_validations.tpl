{{/* Compile all validation warnings into a single message and call fail. */}}
{{- define "retool.validationRules" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "retool.validationRules.internalWorker" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{- define "retool.validationRules.internalWorker" -}}
{{- if not (or (not (.Values.internalWorker.enabled)) (and (.Values.internalWorker.enabled) (or (include "retool.temporal.enabled" .) (include "retool.workflows.enabled" .)))) -}}
internalWorker:
  Internal worker is enabled (via internalWorker.enabled), but Temporal is not enabled via retool-temporal-services-helm.enabled or workflows.temporal.enabled or via Retool's Managed Temporal for Retool Workflows (via workflows.enabled explicitly, or workflows.enabled implicitly based on image.tag > 3.6.11)
{{- end -}}
{{- end -}}
