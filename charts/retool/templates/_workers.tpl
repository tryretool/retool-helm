{{- define "retool.worker.deployment" -}}

{{- $ := .context -}}
{{- $worker := .worker -}}

{{- if $worker.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $worker.name }}
  labels:
    {{- $worker.selectorLabels | nindent 4 }}
    {{- $worker.labels | nindent 4 }}
    {{- include "retool.labels" $ | nindent 4 }}
{{- if $.Values.deployment.annotations }}
  annotations:
{{ toYaml $.Values.deployment.annotations | indent 4 }}
{{- end }}
spec:
  replicas: {{ $worker.replicaCount }}
  selector:
    matchLabels:
      {{- $worker.selectorLabels | nindent 6 }}
  revisionHistoryLimit: {{ $.Values.revisionHistoryLimit }}
  template:
    metadata:
      annotations:
{{- if $worker.prometheusAnnotations }}
        prometheus.io/job: {{ $worker.name }}
        prometheus.io/scrape: 'true'
        prometheus.io/port: '{{ $worker.metricsPort }}'
{{- end }}
{{- if $.Values.podAnnotations }}
{{ toYaml $.Values.podAnnotations | indent 8 }}
{{- end }}
{{- if $.Values.backend.annotations }}
{{ toYaml $.Values.backend.annotations | indent 8 }}
{{- end }}
{{- if $worker.annotations }}
{{ toYaml $worker.annotations | indent 8 }}
{{- end }}
      labels:
        {{- $worker.selectorLabels | nindent 8 }}
        {{- $worker.labels | nindent 8 }}
        {{- include "retool.labels" $ | nindent 8 }}
{{- if $.Values.podLabels }}
{{ toYaml $.Values.podLabels | indent 8 }}
{{- end }}
    spec:
      serviceAccountName: {{ template "retool.serviceAccountName" $ }}
      {{- if $.Values.priorityClassName }}
      priorityClassName: "{{ $.Values.priorityClassName }}"
      {{- end }}
{{- if $.Values.initContainers }}
      initContainers:
{{- range $key, $value := $.Values.initContainers }}
      - name: "{{ $key }}"
{{ toYaml $value | indent 8 }}
{{- end }}
{{- end }}
      containers:
      - name: {{ $worker.containerName }}
        image: "{{ $.Values.image.repository }}:{{ required "Please set a value for .Values.image.tag" $.Values.image.tag }}"
        imagePullPolicy: {{ $.Values.image.pullPolicy }}
        args:
          - bash
          - -c
          - chmod -R +x ./docker_scripts; sync; ./docker_scripts/wait-for-it.sh -t 0 {{ template "retool.postgresql.host" $ }}:{{ template "retool.postgresql.port" $ }}; ./docker_scripts/start_api.sh
        {{- if $.Values.commandline.args }}
{{ toYaml $.Values.commandline.args | indent 10 }}
        {{- end }}
        env:
          - name: DEPLOYMENT_TEMPLATE_TYPE
            value: {{ template "retool.deploymentTemplateType" $ }}
          - name: DEPLOYMENT_TEMPLATE_VERSION
            value: {{ template "retool.deploymentTemplateVersion" $ }}
          - name: NODE_ENV
            value: production
          {{- if $worker.nodeOptions }}
          - name: NODE_OPTIONS
            value: {{ $worker.nodeOptions }}
          {{- end }}
          - name: SERVICE_TYPE
            value: {{ $worker.serviceType }}
          {{- if $worker.taskqueue }}
          - name: WORKER_TEMPORAL_TASKQUEUE
            value: {{ $worker.taskqueue }}
          {{- end }}
          - name: DBCONNECTOR_POSTGRES_POOL_MAX_SIZE
            value: "100"
          {{- if $.Values.dbconnector.enabled }}
          - name: DB_CONNECTOR_HOST
            value: http://{{ template "retool.fullname" $ }}-dbconnector
          - name: DB_CONNECTOR_PORT
            value: {{ $.Values.dbconnector.port | quote }}
          {{- if $.Values.dbconnector.java.enabled }}
          - name: JAVA_DBCONNECTOR_HOST
            value: http://{{ template "retool.fullname" $ }}-dbconnector
          - name: JAVA_DBCONNECTOR_PORT
            value: {{ $.Values.dbconnector.java.port | quote }}
          {{- end }}
          {{ end }}
          - name: DBCONNECTOR_QUERY_TIMEOUT_MS
          {{- if $worker.dbConnectorTimeout }}
            value: {{ $worker.dbConnectorTimeout | quote}}
          {{- else if $.Values.config.dbConnectorTimeout }}
            value: {{ $.Values.config.dbConnectorTimeout | quote}}
          {{- else }}
            value: "5400000"
          {{- end }}
          - name: DISABLE_DATABASE_MIGRATIONS
            value: "true"
          {{- $temporalConfig := $worker.temporalConfig | default $.Values.workflows.temporal | default $.Values.temporal }}
          {{- if or (index $.Values "retool-temporal-services-helm" "enabled") ($temporalConfig).enabled }}
          - name: WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST
            value: {{ template "retool.temporal.host" $ }}
          - name: WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_PORT
            value: {{ template "retool.temporal.port" $ }}
          - name: WORKFLOW_TEMPORAL_CLUSTER_NAMESPACE
            value: {{ template "retool.temporal.namespace" $ }}
          {{- end }}
          {{- if ($temporalConfig).sslEnabled }}
          - name: WORKFLOW_TEMPORAL_TLS_ENABLED
            value: "true"
          {{- if (and ($temporalConfig).sslCert ($temporalConfig).sslKey) }}
          - name: WORKFLOW_TEMPORAL_TLS_CRT
            value: {{ $temporalConfig.sslCert }}
          - name: WORKFLOW_TEMPORAL_TLS_KEY
            valueFrom:
              secretKeyRef:
              {{- if ($temporalConfig).sslKeySecretName }}
                name: {{ $temporalConfig.sslKeySecretName }}
                key: {{ ($temporalConfig).sslKeySecretKey | default "temporal-tls-key" }}
              {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: "temporal-tls-key"
              {{- end }}
          {{- end }}
          {{- end }}
          {{- if $worker.healthcheckPort }}
          - name: WORKFLOW_WORKER_HEALTHCHECK_PORT
            value: "{{ $worker.healthcheckPort }}"
          {{- end }}
          - name: WORKFLOW_BACKEND_HOST
            value: http://{{ include "retool.workflowBackend.name" $ }}
          - name: CLIENT_ID
            value: {{ default "" $.Values.config.auth.google.clientId }}
          - name: COOKIE_INSECURE
            value: {{ $.Values.config.useInsecureCookies | quote }}
          - name: POSTGRES_HOST
            value: {{ template "retool.postgresql.host" $ }}
          - name: POSTGRES_PORT
            value: {{ template "retool.postgresql.port" $ }}
          - name: POSTGRES_DB
            value: {{ template "retool.postgresql.database" $ }}
          - name: POSTGRES_USER
            value: {{ template "retool.postgresql.user" $ }}
          - name: POSTGRES_SSL_ENABLED
            value: {{ template "retool.postgresql.ssl_enabled" $ }}
          {{- if include "retool.codeExecutor.enabled" $ }}
          - name: CODE_EXECUTOR_INGRESS_DOMAIN
            value: http://{{ template "retool.codeExecutor.name" $ }}
          {{- end }}

          {{- include "retool.telemetry.includeEnvVars" $ | nindent 10 }}

          {{- if and (($worker.config.otelCollector).enabled) (($worker.config.otelCollector).endpoint) }}
          - name: OTEL_EXPORTER_OTLP_ENDPOINT
             value: {{ ($worker.config.otelCollector).endpoint }}
          {{- else if ($worker.config.otelCollector).enabled }}
          - name: HOST_IP
            valueFrom:
              fieldRef:
                fieldPath: status.hostIP
          - name: OTEL_EXPORTER_OTLP_ENDPOINT
            value: "http://$(HOST_IP):4317"
          {{- end }}
          {{- if include "shouldIncludeConfigSecretsEnvVars" $ }}
          - name: LICENSE_KEY
            valueFrom:
              secretKeyRef:
                {{- if $.Values.config.licenseKeySecretName }}
                name: {{ $.Values.config.licenseKeySecretName }}
                key: {{ $.Values.config.licenseKeySecretKey | default "license-key" }}
                {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: license-key
                {{- end }}
          - name: JWT_SECRET
            valueFrom:
              secretKeyRef:
                {{- if $.Values.config.jwtSecretSecretName }}
                name: {{ $.Values.config.jwtSecretSecretName }}
                key: {{ $.Values.config.jwtSecretSecretKey | default "jwt-secret" }}
                {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: jwt-secret
                {{- end }}
          - name: ENCRYPTION_KEY
            valueFrom:
              secretKeyRef:
                {{- if $.Values.config.encryptionKeySecretName }}
                name: {{ $.Values.config.encryptionKeySecretName }}
                key: {{ $.Values.config.encryptionKeySecretKey | default "encryption-key" }}
                {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: encryption-key
                {{- end }}
          - name: POSTGRES_PASSWORD
            valueFrom:
              secretKeyRef:
          {{- if  $.Values.postgresql.enabled }}
                name: {{ template "retool.postgresql.fullname" $ }}
                key: postgres-password
          {{- else }}
                {{- if $.Values.config.postgresql.passwordSecretName }}
                name: {{ $.Values.config.postgresql.passwordSecretName }}
                key: {{ $.Values.config.postgresql.passwordSecretKey | default "postgresql-password" }}
                {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: postgresql-password
                {{- end }}
          {{- end }}
          - name: CLIENT_SECRET
            valueFrom:
              secretKeyRef:
                {{- if $.Values.config.auth.google.clientSecretSecretName }}
                name: {{ $.Values.config.auth.google.clientSecretSecretName }}
                key: {{ $.Values.config.auth.google.clientSecretSecretKey | default "google-client-secret" }}
                {{- else }}
                name: {{ template "retool.fullname" $ }}
                key: google-client-secret
                {{- end }}
          {{- end }}
          {{- range $key, $value := $.Values.env }}
          - name: "{{ $key }}"
            value: "{{ $value }}"
          {{- end }}
          {{- range $.Values.environmentSecrets }}
          - name: {{ .name }}
            valueFrom:
              secretKeyRef:
                name: {{ .secretKeyRef.name }}
                key: {{ .secretKeyRef.key }}
          {{- end }}
          {{- with $.Values.environmentVariables }}
{{ toYaml . | indent 10 }}
          {{- end }}
          {{- with $worker.config.environmentVariables }}
{{ toYaml . | indent 10 }}
          {{- end }}
        {{- if $.Values.externalSecrets.enabled }}
        envFrom:
        - secretRef:
            name: {{ $.Values.externalSecrets.name }}
        {{- range $.Values.externalSecrets.secrets }}
        - secretRef:
            name: {{ .name }}
        {{- end }}
        {{- end }}
        {{- if $.Values.externalSecrets.externalSecretsOperator.enabled  }}
        envFrom:
        {{- range $.Values.externalSecrets.externalSecretsOperator.secretRef }}
        - secretRef:
            name: {{ .name }}
            optional: {{ .optional | default false }}
        {{- end }}
        {{- end }}
        ports:
        {{- if $worker.healthcheckPort }}
        - containerPort: {{ $worker.healthcheckPort }}
          name: http-server
          protocol: TCP
        {{- end }}
        {{- if $worker.metricsPort }}
        - containerPort: {{ $worker.metricsPort }}
          name: http-metrics
          protocol: TCP
        {{- end }}

{{- if $.Values.livenessProbe.enabled }}
        livenessProbe:
          httpGet:
            path: {{ $.Values.livenessProbe.path }}
            port: {{ $worker.healthcheckPort | default $.Values.service.internalPort }}
          initialDelaySeconds: {{ $.Values.livenessProbe.initialDelaySeconds }}
          timeoutSeconds: {{ $.Values.livenessProbe.timeoutSeconds }}
          failureThreshold:  {{ $.Values.livenessProbe.failureThreshold }}
{{- end }}
{{- if $.Values.readinessProbe.enabled }}
        readinessProbe:
          httpGet:
            path: {{ $.Values.readinessProbe.path }}
            port: {{ $worker.healthcheckPort | default $.Values.service.internalPort }}
          initialDelaySeconds: {{ $.Values.readinessProbe.initialDelaySeconds }}
          timeoutSeconds: {{ $.Values.readinessProbe.timeoutSeconds }}
          successThreshold: {{ $.Values.readinessProbe.successThreshold }}
          periodSeconds: {{ $.Values.readinessProbe.periodSeconds }}
{{- end }}
        resources:
{{ toYaml $worker.resources | indent 10 }}
        volumeMounts:
        {{- range $configFile := (keys $.Values.files) }}
        - name: {{ template "retool.name" $ }}
          mountPath: "/usr/share/retool/config/{{ $configFile }}"
          subPath: {{ $configFile }}
        {{- end }}
{{- if $.Values.extraVolumeMounts }}
{{ toYaml $.Values.extraVolumeMounts | indent 8 }}
{{- end }}
{{- if $.Values.securityContext.extraContainerSecurityContext }}
        securityContext:
{{ toYaml $.Values.securityContext.extraContainerSecurityContext | indent 10 }}
{{- end }}
{{- with $.Values.extraContainers }}
{{ tpl . $ | indent 6 }}
{{- end }}
{{- range $.Values.extraConfigMapMounts }}
        - name: {{ .name }}
          mountPath: {{ .mountPath }}
          subPath: {{ .subPath }}
{{- end }}
    {{- if $.Values.image.pullSecrets }}
      imagePullSecrets:
{{ toYaml $.Values.image.pullSecrets | indent 8 }}
    {{- end }}
    {{- if $.Values.affinity }}
      affinity:
{{ toYaml $.Values.affinity | indent 8 }}
    {{- end }}
    {{- if $.Values.nodeSelector }}
      nodeSelector:
{{ toYaml $.Values.nodeSelector | indent 8 }}
    {{- end }}
      tolerations:
{{ toYaml $.Values.tolerations | indent 8 }}
{{- if $.Values.securityContext.enabled }}
      securityContext:
        runAsUser: {{ $.Values.securityContext.runAsUser }}
        fsGroup: {{ $.Values.securityContext.fsGroup }}
{{- if $.Values.securityContext.extraSecurityContext }}
{{ toYaml $.Values.securityContext.extraSecurityContext | indent 8 }}
{{- end }}
{{- end }}
      volumes:
{{- range $.Values.extraConfigMapMounts }}
        - name: {{ .name }}
          configMap:
            name: {{ .configMap }}
{{- end }}
{{- if $.Values.extraVolumes }}
{{ toYaml $.Values.extraVolumes | indent 8 }}
{{- end }}
---
{{- if $.Values.podDisruptionBudget }}
{{- if semverCompare ">=1.21-0" $.Capabilities.KubeVersion.Version -}}
apiVersion: policy/v1
{{- else -}}
apiVersion: policy/v1beta1
{{- end }}
kind: PodDisruptionBudget
metadata:
  name: {{ $worker.name }}
spec:
  {{ toYaml $.Values.podDisruptionBudget }}
  selector:
    matchLabels:
      {{- $worker.selectorLabels | nindent 6 }}
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $worker.name }}
spec:
  selector:
    {{- $worker.selectorLabels | nindent 4 }}
  ports:
{{- if $worker.healthcheckPort }}
  - protocol: TCP
    port: {{ $worker.healthcheckPort }}
    targetPort: {{ $worker.healthcheckPort }}
    name: http-server
{{- end }}
{{- if $worker.metricsPort }}
  - protocol: TCP
    port: {{ $worker.metricsPort }}
    targetPort: http-metrics
    name: http-metrics
{{- end }}
{{- end }}
{{- end }}
