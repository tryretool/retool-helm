{{/* Compile all validation warnings into a single message and call fail. */}}
{{- define "retool.validationRules" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "retool.validationRules.workers" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{- define "retool.validationRules.workers" -}}
{{- if not (or (not (include "retool.worker.enabled" .)) (and (include "retool.worker.enabled" .) (include "retool.temporal.enabled" .))) -}}
workers:
  Workers are enabled (via internalWorker.enabled, workflows.enabled explicitly, or workflows.enabled implicitly based on image.tag > 3.6.11), but Temporal is not enabled via retool-temporal-services-helm.enabled or workflows.temporal.enabled
{{- end -}}
{{- end -}}
