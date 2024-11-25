
{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "airflow.fullname" -}}
  {{- if not .Values.useStandardNaming }}
    {{- .Release.Name }}
  {{- else if .Values.fullnameOverride }}
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

{{- define "airflow.serviceAccountName" -}}
  {{ if .Values.fullnameOverride }}
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

{{/* Standard Airflow environment variables */}}
{{- define "standard_airflow_environment" }}
  # Hard Coded Airflow Envs
  {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__CORE__FERNET_KEY }}
  - name: AIRFLOW__CORE__FERNET_KEY
    valueFrom:
      secretKeyRef:
        name: {{ template "fernet_key_secret" . }}
        key: fernet-key
  {{- end }}
  - name: AIRFLOW_HOME
    value: {{ .Values.airflowHome }}
  # For Airflow <2.3, backward compatibility; moved to [database] in 2.3
  {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__CORE__SQL_ALCHEMY_CONN }}
  - name: AIRFLOW__CORE__SQL_ALCHEMY_CONN
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_metadata_secret" . }}
        key: connection
  {{- end }}
  {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__DATABASE__SQL_ALCHEMY_CONN }}
  - name: AIRFLOW__DATABASE__SQL_ALCHEMY_CONN
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_metadata_secret" . }}
        key: connection
  {{- end }}
  {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW_CONN_AIRFLOW_DB }}
  - name: AIRFLOW_CONN_AIRFLOW_DB
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_metadata_secret" . }}
        key: connection
  {{- end }}
  {{- if and .Values.workers.keda.enabled (or (eq .Values.data.metadataConnection.protocol "mysql") (and .Values.pgbouncer.enabled (not .Values.workers.keda.usePgbouncer))) }}
  - name: KEDA_DB_CONN
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_metadata_secret" . }}
        key: kedaConnection
  {{- end }}
  {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__WEBSERVER__SECRET_KEY }}
  - name: AIRFLOW__WEBSERVER__SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: {{ template "webserver_secret_key_secret" . }}
        key: webserver-secret-key
  {{- end }}
  {{- if or (eq .Values.executor "CeleryExecutor") (eq .Values.executor "CeleryKubernetesExecutor") }}
    {{- if or (semverCompare "<2.4.0" .Values.airflowVersion) (.Values.data.resultBackendSecretName) (.Values.data.resultBackendConnection) }}
    {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__CELERY__CELERY_RESULT_BACKEND }}
  # (Airflow 1.10.* variant)
  - name: AIRFLOW__CELERY__CELERY_RESULT_BACKEND
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_result_backend_secret" . }}
        key: connection
    {{- end }}
    {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__CELERY__RESULT_BACKEND }}
  - name: AIRFLOW__CELERY__RESULT_BACKEND
    valueFrom:
      secretKeyRef:
        name: {{ template "airflow_result_backend_secret" . }}
        key: connection
    {{- end }}
    {{- end }}
    {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__CELERY__BROKER_URL }}
  - name: AIRFLOW__CELERY__BROKER_URL
    valueFrom:
      secretKeyRef:
        name: {{ default (printf "%s-broker-url" .Release.Name) .Values.data.brokerUrlSecretName }}
        key: connection
    {{- end }}
  {{- end }}
  {{- if .Values.elasticsearch.enabled }}
  # The elasticsearch variables were updated to the shorter names in v1.10.4
    {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__ELASTICSEARCH__HOST }}
  - name: AIRFLOW__ELASTICSEARCH__HOST
    valueFrom:
      secretKeyRef:
        name: {{ template "elasticsearch_secret" . }}
        key: connection
    {{- end }}
    {{- if .Values.enableBuiltInSecretEnvVars.AIRFLOW__ELASTICSEARCH__ELASTICSEARCH_HOST }}
  # This is the older format for these variable names, kept here for backward compatibility
  - name: AIRFLOW__ELASTICSEARCH__ELASTICSEARCH_HOST
    valueFrom:
      secretKeyRef:
        name: {{ template "elasticsearch_secret" . }}
        key: connection
    {{- end }}
  {{- end }}
{{- end }}

{{/* User defined Airflow environment variables */}}
{{- define "custom_airflow_environment" }}
  # Dynamically created environment variables
  {{- range $i, $config := .Values.env }}
  - name: {{ $config.name }}
    value: {{ $config.value | quote }}
    {{- if or (eq $.Values.executor "KubernetesExecutor") (eq $.Values.executor "LocalKubernetesExecutor") (eq $.Values.executor "CeleryKubernetesExecutor") }}
  - name: AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__{{ $config.name }}
    value: {{ $config.value | quote }}
    {{- end }}
  {{- end }}
  # Dynamically created secret envs
  {{- range $i, $config := .Values.secret }}
  - name: {{ $config.envName }}
    valueFrom:
      secretKeyRef:
        name: {{ $config.secretName }}
        key: {{ default "value" $config.secretKey }}
  {{- end }}
  {{- if or (eq $.Values.executor "LocalKubernetesExecutor") (eq $.Values.executor "KubernetesExecutor") (eq $.Values.executor "CeleryKubernetesExecutor") }}
    {{- range $i, $config := .Values.secret }}
  - name: AIRFLOW__KUBERNETES_SECRETS__{{ $config.envName }}
    value: {{ printf "%s=%s" $config.secretName $config.secretKey }}
    {{- end }}
  {{ end }}
  # Extra env
  {{- $Global := . }}
  {{- with .Values.extraEnv }}
    {{- tpl . $Global | nindent 2 }}
  {{- end }}
{{- end }}

{{/* User defined Airflow environment from */}}
{{- define "custom_airflow_environment_from" }}
  {{- $Global := . }}
  {{- with .Values.extraEnvFrom }}
    {{- tpl . $Global | nindent 2 }}
  {{- end }}
{{- end }}

{{/* User defined gitSync container environment from */}}
{{- define "custom_git_sync_environment_from" }}
  {{- $Global := . }}
  {{- with .Values.dags.gitSync.envFrom }}
    {{- tpl . $Global | nindent 2 }}
  {{- end }}
{{- end }}

{{/*  Git ssh key volume */}}
{{- define "git_sync_ssh_key_volume" }}
- name: git-sync-ssh-key
  secret:
    secretName: {{ template "git_sync_ssh_key" . }}
    defaultMode: 288
{{- end }}

{{/*  Git sync container */}}
{{- define "git_sync_container" }}
- name: {{ .Values.dags.gitSync.containerName }}{{ if .is_init }}-init{{ end }}
  image: {{ template "git_sync_image" . }}
  imagePullPolicy: {{ .Values.images.gitSync.pullPolicy }}
  securityContext: {{- include "localContainerSecurityContext" .Values.dags.gitSync | nindent 4 }}
  envFrom: {{- include "custom_git_sync_environment_from" . | default "\n  []" | indent 2 }}
  env:
    {{- if or .Values.dags.gitSync.sshKeySecret .Values.dags.gitSync.sshKey }}
    - name: GIT_SSH_KEY_FILE
      value: "/etc/git-secret/ssh"
    - name: GITSYNC_SSH_KEY_FILE
      value: "/etc/git-secret/ssh"
    - name: GIT_SYNC_SSH
      value: "true"
    - name: GITSYNC_SSH
      value: "true"
    {{- if .Values.dags.gitSync.knownHosts }}
    - name: GIT_KNOWN_HOSTS
      value: "true"
    - name: GITSYNC_SSH_KNOWN_HOSTS
      value: "true"
    - name: GIT_SSH_KNOWN_HOSTS_FILE
      value: "/etc/git-secret/known_hosts"
    - name: GITSYNC_SSH_KNOWN_HOSTS_FILE
      value: "/etc/git-secret/known_hosts"
    {{- else }}
    - name: GIT_KNOWN_HOSTS
      value: "false"
    - name: GITSYNC_SSH_KNOWN_HOSTS
      value: "false"
    {{- end }}
    {{ else if .Values.dags.gitSync.credentialsSecret }}
    - name: GIT_SYNC_USERNAME
      valueFrom:
        secretKeyRef:
          name: {{ .Values.dags.gitSync.credentialsSecret | quote }}
          key: GIT_SYNC_USERNAME
    - name: GITSYNC_USERNAME
      valueFrom:
        secretKeyRef:
          name: {{ .Values.dags.gitSync.credentialsSecret | quote }}
          key: GITSYNC_USERNAME
    - name: GIT_SYNC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.dags.gitSync.credentialsSecret | quote }}
          key: GIT_SYNC_PASSWORD
    - name: GITSYNC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ .Values.dags.gitSync.credentialsSecret | quote }}
          key: GITSYNC_PASSWORD
    {{- end }}
    - name: GIT_SYNC_REV
      value: {{ .Values.dags.gitSync.rev | quote }}
    - name: GITSYNC_REF
      value: {{ .Values.dags.gitSync.ref | quote }}
    - name: GIT_SYNC_BRANCH
      value: {{ .Values.dags.gitSync.branch | quote }}
    - name: GIT_SYNC_REPO
      value: {{ .Values.dags.gitSync.repo | quote }}
    - name: GITSYNC_REPO
      value: {{ .Values.dags.gitSync.repo | quote }}
    - name: GIT_SYNC_DEPTH
      value: {{ .Values.dags.gitSync.depth | quote }}
    - name: GITSYNC_DEPTH
      value: {{ .Values.dags.gitSync.depth | quote }}
    - name: GIT_SYNC_ROOT
      value: "/git"
    - name: GITSYNC_ROOT
      value: "/git"
    - name: GIT_SYNC_DEST
      value: "repo"
    - name: GITSYNC_LINK
      value: "repo"
    - name: GIT_SYNC_ADD_USER
      value: "true"
    - name: GITSYNC_ADD_USER
      value: "true"
    {{- if .Values.dags.gitSync.wait }}
    - name: GIT_SYNC_WAIT
      value: {{ .Values.dags.gitSync.wait | quote }}
    {{- end }}
    - name: GITSYNC_PERIOD
      value: {{ .Values.dags.gitSync.period | quote }}
    - name: GIT_SYNC_MAX_SYNC_FAILURES
      value: {{ .Values.dags.gitSync.maxFailures | quote }}
    - name: GITSYNC_MAX_FAILURES
      value: {{ .Values.dags.gitSync.maxFailures | quote }}
    {{- if .is_init }}
    - name: GIT_SYNC_ONE_TIME
      value: "true"
    - name: GITSYNC_ONE_TIME
      value: "true"
    {{- end }}
    {{- with .Values.dags.gitSync.env }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  resources: {{ toYaml .Values.dags.gitSync.resources | nindent 4 }}
  volumeMounts:
  - name: dags
    mountPath: /git
  {{- if or .Values.dags.gitSync.sshKeySecret .Values.dags.gitSync.sshKey }}
  - name: git-sync-ssh-key
    mountPath: /etc/git-secret/ssh
    readOnly: true
    subPath: gitSshKey
  {{- if .Values.dags.gitSync.knownHosts }}
  - name: config
    mountPath: /etc/git-secret/known_hosts
    readOnly: true
    subPath: known_hosts
  {{- end }}
  {{- end }}
  {{- if .Values.dags.gitSync.extraVolumeMounts }}
    {{- tpl (toYaml .Values.dags.gitSync.extraVolumeMounts) . | nindent 2 }}
  {{- end }}
  {{- if and .Values.dags.gitSync.containerLifecycleHooks (not .is_init) }}
  lifecycle: {{- tpl (toYaml .Values.dags.gitSync.containerLifecycleHooks) . | nindent 4 }}
  {{- end }}
{{- end }}

{{/* This helper will change when customers deploy a new image */}}
{{- define "airflow_image" -}}
  {{- $repository := .Values.images.airflow.repository | default .Values.defaultAirflowRepository -}}
  {{- $tag := .Values.images.airflow.tag | default .Values.defaultAirflowTag -}}
  {{- $digest := .Values.images.airflow.digest | default .Values.defaultAirflowDigest -}}
  {{- if $digest }}
    {{- printf "%s@%s" $repository $digest -}}
  {{- else }}
    {{- printf "%s:%s" $repository $tag -}}
  {{- end }}
{{- end }}

{{- define "pod_template_image" -}}
  {{- printf "%s:%s" (.Values.images.pod_template.repository | default .Values.defaultAirflowRepository) (.Values.images.pod_template.tag | default .Values.defaultAirflowTag) }}
{{- end }}

{{/* This helper is used for airflow containers that do not need the users code */}}
{{ define "default_airflow_image" -}}
  {{- $repository := .Values.defaultAirflowRepository -}}
  {{- $tag := .Values.defaultAirflowTag -}}
  {{- $digest := .Values.defaultAirflowDigest -}}
  {{- if $digest }}
    {{- printf "%s@%s" $repository $digest -}}
  {{- else }}
    {{- printf "%s:%s" $repository $tag -}}
  {{- end }}
{{- end }}

{{ define "airflow_image_for_migrations" -}}
  {{- if .Values.images.useDefaultImageForMigration }}
    {{- template "default_airflow_image" . }}
  {{- else }}
    {{- template "airflow_image" . }}
  {{- end }}
{{- end }}

{{- define "flower_image" -}}
  {{- printf "%s:%s" (.Values.images.flower.repository | default .Values.defaultAirflowRepository) (.Values.images.flower.tag | default .Values.defaultAirflowTag) }}
{{- end }}

{{- define "statsd_image" -}}
  {{- printf "%s:%s" .Values.images.statsd.repository .Values.images.statsd.tag }}
{{- end }}

{{- define "redis_image" -}}
  {{- printf "%s:%s" .Values.images.redis.repository .Values.images.redis.tag }}
{{- end }}

{{- define "pgbouncer_image" -}}
  {{- printf "%s:%s" .Values.images.pgbouncer.repository .Values.images.pgbouncer.tag }}
{{- end }}

{{- define "pgbouncer_exporter_image" -}}
  {{- printf "%s:%s" .Values.images.pgbouncerExporter.repository .Values.images.pgbouncerExporter.tag }}
{{- end }}

{{- define "git_sync_image" -}}
  {{- printf "%s:%s" .Values.images.gitSync.repository .Values.images.gitSync.tag }}
{{- end }}

{{- define "fernet_key_secret" -}}
  {{- default (printf "%s-fernet-key" .Release.Name) .Values.fernetKeySecretName }}
{{- end }}

{{- define "webserver_secret_key_secret" -}}
  {{- default (printf "%s-webserver-secret-key" (include "airflow.fullname" .)) .Values.webserverSecretKeySecretName }}
{{- end }}

{{- define "redis_password_secret" -}}
  {{- default (printf "%s-redis-password" .Release.Name) .Values.redis.passwordSecretName }}
{{- end }}

{{- define "airflow_metadata_secret" -}}
  {{- default (printf "%s-metadata" (include "airflow.fullname" .)) .Values.data.metadataSecretName }}
{{- end }}

{{- define "airflow_result_backend_secret" -}}
  {{- default (printf "%s-result-backend" (include "airflow.fullname" .)) .Values.data.resultBackendSecretName }}
{{- end }}

{{- define "airflow_pod_template_file" -}}
  {{- printf "%s/pod_templates" .Values.airflowHome }}
{{- end }}

{{- define "pgbouncer_config_secret" -}}
  {{- default (printf "%s-pgbouncer-config" (include "airflow.fullname" .)) .Values.pgbouncer.configSecretName }}
{{- end }}

{{- define "pgbouncer_certificates_secret" -}}
  {{- printf "%s-pgbouncer-certificates" (include "airflow.fullname" .) }}
{{- end }}

{{- define "pgbouncer_stats_secret" -}}
  {{- default (printf "%s-pgbouncer-stats" (include "airflow.fullname" .)) .Values.pgbouncer.metricsExporterSidecar.statsSecretName }}
{{- end }}

{{- define "registry_secret" -}}
  {{- default (printf "%s-registry" (include "airflow.fullname" .)) .Values.registry.secretName }}
{{- end }}

{{- define "elasticsearch_secret" -}}
  {{- default (printf "%s-elasticsearch" (include "airflow.fullname" .)) .Values.elasticsearch.secretName }}
{{- end }}

{{- define "flower_secret" -}}
  {{- default (printf "%s-flower" (include "airflow.fullname" .)) .Values.flower.secretName }}
{{- end }}

{{- define "kerberos_keytab_secret" -}}
  {{- printf "%s-kerberos-keytab" (include "airflow.fullname" .) }}
{{- end }}

{{- define "kerberos_ccache_path" -}}
  {{- printf "%s/%s" .Values.kerberos.ccacheMountPath .Values.kerberos.ccacheFileName }}
{{- end }}

{{/* Create the name of the git sync ssh secret to use */}}
{{- define "git_sync_ssh_key" -}}
  {{- default (printf "%s-ssh-secret" (include "airflow.fullname" .)) .Values.dags.gitSync.sshKeySecret }}
{{- end }}

{{- define "celery_executor_namespace" -}}
  {{- if semverCompare ">=2.7.0" .Values.airflowVersion }}
    {{- print "airflow.providers.celery.executors.celery_executor.app" -}}
  {{- else }}
    {{- print "airflow.executors.celery_executor.app" -}}
  {{- end }}
{{- end }}

{{- define "pgbouncer_config" -}}
{{ $resultBackendConnection := .Values.data.resultBackendConnection | default .Values.data.metadataConnection }}
{{ $pgMetadataHost := .Values.data.metadataConnection.host | default (printf "%s-%s.%s" .Release.Name "postgresql" .Release.Namespace) }}
{{ $pgResultBackendHost := $resultBackendConnection.host | default (printf "%s-%s.%s" .Release.Name "postgresql" .Release.Namespace) }}
[databases]
{{ .Release.Name }}-metadata = host={{ $pgMetadataHost }} dbname={{ .Values.data.metadataConnection.db }} port={{ .Values.data.metadataConnection.port }} pool_size={{ .Values.pgbouncer.metadataPoolSize }} {{ .Values.pgbouncer.extraIniMetadata | default "" }}
{{ .Release.Name }}-result-backend = host={{ $pgResultBackendHost }} dbname={{ $resultBackendConnection.db }} port={{ $resultBackendConnection.port }} pool_size={{ .Values.pgbouncer.resultBackendPoolSize }} {{ .Values.pgbouncer.extraIniResultBackend | default "" }}

[pgbouncer]
pool_mode = transaction
listen_port = {{ .Values.ports.pgbouncer }}
listen_addr = *
auth_type = {{ .Values.pgbouncer.auth_type }}
auth_file = {{ .Values.pgbouncer.auth_file }}
stats_users = {{ .Values.data.metadataConnection.user }}
ignore_startup_parameters = extra_float_digits
max_client_conn = {{ .Values.pgbouncer.maxClientConn }}
verbose = {{ .Values.pgbouncer.verbose }}
log_disconnections = {{ .Values.pgbouncer.logDisconnections }}
log_connections = {{ .Values.pgbouncer.logConnections }}

server_tls_sslmode = {{ .Values.pgbouncer.sslmode }}
server_tls_ciphers = {{ .Values.pgbouncer.ciphers }}

{{- if .Values.pgbouncer.ssl.ca }}
server_tls_ca_file = /etc/pgbouncer/root.crt
{{- end }}
{{- if .Values.pgbouncer.ssl.cert }}
server_tls_cert_file = /etc/pgbouncer/server.crt
{{- end }}
{{- if .Values.pgbouncer.ssl.key }}
server_tls_key_file = /etc/pgbouncer/server.key
{{- end }}

{{- if .Values.pgbouncer.extraIni }}
{{ .Values.pgbouncer.extraIni }}
{{- end }}
{{- end }}

{{ define "pgbouncer_users" }}
{{- $resultBackendConnection := .Values.data.resultBackendConnection | default .Values.data.metadataConnection }}
{{ .Values.data.metadataConnection.user | quote }} {{ .Values.data.metadataConnection.pass | quote }}
{{ $resultBackendConnection.user | quote }} {{ $resultBackendConnection.pass | quote }}
{{- end }}

{{- define "airflow_logs" -}}
  {{- printf "%s/logs" .Values.airflowHome | quote }}
{{- end }}

{{- define "airflow_logs_no_quote" -}}
  {{- printf "%s/logs" .Values.airflowHome }}
{{- end }}

{{- define "airflow_logs_volume_claim" -}}
  {{- if .Values.logs.persistence.existingClaim }}
    {{- .Values.logs.persistence.existingClaim }}
  {{- else }}
    {{- printf "%s-logs" .Release.Name }}
  {{- end }}
{{- end }}

{{- define "airflow_dags" -}}
  {{- if .Values.dags.mountPath }}
    {{- if .Values.dags.gitSync.enabled }}
      {{- printf "%s/repo/%s" .Values.dags.mountPath .Values.dags.gitSync.subPath }}
    {{- else }}
      {{- printf "%s" .Values.dags.mountPath }}
    {{- end }}
  {{- else }}
    {{- if .Values.dags.gitSync.enabled }}
      {{- printf "%s/dags/repo/%s" .Values.airflowHome .Values.dags.gitSync.subPath }}
    {{- else }}
      {{- printf "%s/dags" .Values.airflowHome }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "airflow_dags_volume_claim" -}}
  {{- if .Values.dags.persistence.existingClaim }}
    {{- .Values.dags.persistence.existingClaim }}
  {{- else }}
    {{- printf "%s-dags" .Release.Name }}
  {{- end }}
{{- end }}

{{- define "airflow_dags_mount" -}}
- name: dags
  {{- if .Values.dags.mountPath }}
  mountPath: {{ .Values.dags.mountPath }}
  {{- else }}
  mountPath: {{ printf "%s/dags" .Values.airflowHome }}
  {{- end }}
  {{- if .Values.dags.persistence.subPath }}
  subPath: {{ .Values.dags.persistence.subPath }}
  {{- end }}
  readOnly: {{ .Values.dags.gitSync.enabled | ternary "True" "False" }}
{{- end }}

{{- define "airflow_config_path" -}}
  {{- printf "%s/airflow.cfg" .Values.airflowHome | quote }}
{{- end }}

{{- define "airflow_webserver_config_path" -}}
  {{- printf "%s/webserver_config.py" .Values.airflowHome | quote }}
{{- end }}

{{- define "airflow_webserver_config_configmap_name" -}}
  {{- default (printf "%s-webserver-config" .Release.Name) .Values.webserver.webserverConfigConfigMapName }}
{{- end }}

{{- define "airflow_webserver_config_mount" -}}
- name: webserver-config
  mountPath: {{ template "airflow_webserver_config_path" . }}
  subPath: webserver_config.py
  readOnly: True
{{- end }}

{{- define "airflow_local_setting_path" -}}
  {{- printf "%s/config/airflow_local_settings.py" .Values.airflowHome | quote }}
{{- end }}

{{- define "airflow_config" -}}
  {{- printf "%s-config" (include "airflow.fullname" .) }}
{{- end }}

{{- define "airflow_config_mount" -}}
- name: config
  mountPath: {{ template "airflow_config_path" . }}
  subPath: airflow.cfg
  readOnly: true
  {{- if .Values.airflowLocalSettings }}
- name: config
  mountPath: {{ template "airflow_local_setting_path" . }}
  subPath: airflow_local_settings.py
  readOnly: true
  {{- end }}
{{- end }}

{{/* Create the name of the webserver service account to use */}}
{{- define "webserver.serviceAccountName" -}}
  {{- if .Values.webserver.serviceAccount.create }}
    {{- default (printf "%s-webserver" (include "airflow.serviceAccountName" .)) .Values.webserver.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.webserver.serviceAccount.name }}
  {{- end }}
{{- end }}


{{/* Create the name of the RPC server service account to use */}}
{{- define "rpcServer.serviceAccountName" -}}
  {{- if .Values._rpcServer.serviceAccount.create }}
    {{- default (printf "%s-rpc-server" (include "airflow.serviceAccountName" .)) .Values._rpcServer.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values._rpcServer.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the redis service account to use */}}
{{- define "redis.serviceAccountName" -}}
  {{- if .Values.redis.serviceAccount.create }}
    {{- default (printf "%s-redis" (include "airflow.serviceAccountName" .)) .Values.redis.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.redis.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the flower service account to use */}}
{{- define "flower.serviceAccountName" -}}
  {{- if .Values.flower.serviceAccount.create }}
    {{- default (printf "%s-flower" (include "airflow.serviceAccountName" .)) .Values.flower.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.flower.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the scheduler service account to use */}}
{{- define "scheduler.serviceAccountName" -}}
  {{- if .Values.scheduler.serviceAccount.create }}
    {{- default (printf "%s-scheduler" (include "airflow.serviceAccountName" .)) .Values.scheduler.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.scheduler.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the StatsD service account to use */}}
{{- define "statsd.serviceAccountName" -}}
  {{- if .Values.statsd.serviceAccount.create }}
    {{- default (printf "%s-statsd" (include "airflow.serviceAccountName" .)) .Values.statsd.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.statsd.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the create user job service account to use */}}
{{- define "createUserJob.serviceAccountName" -}}
  {{- if .Values.createUserJob.serviceAccount.create }}
    {{- default (printf "%s-create-user-job" (include "airflow.serviceAccountName" .)) .Values.createUserJob.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.createUserJob.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the migrate database job service account to use */}}
{{- define "migrateDatabaseJob.serviceAccountName" -}}
  {{- if .Values.migrateDatabaseJob.serviceAccount.create }}
    {{- default (printf "%s-migrate-database-job" (include "airflow.serviceAccountName" .)) .Values.migrateDatabaseJob.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.migrateDatabaseJob.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the worker service account to use */}}
{{- define "worker.serviceAccountName" -}}
  {{- if .Values.workers.serviceAccount.create }}
    {{- default (printf "%s-worker" (include "airflow.serviceAccountName" .)) .Values.workers.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.workers.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the triggerer service account to use */}}
{{- define "triggerer.serviceAccountName" -}}
  {{- if .Values.triggerer.serviceAccount.create }}
    {{- default (printf "%s-triggerer" (include "airflow.serviceAccountName" .)) .Values.triggerer.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.triggerer.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the dag processor service account to use */}}
{{- define "dagProcessor.serviceAccountName" -}}
  {{- if .Values.dagProcessor.serviceAccount.create }}
    {{- default (printf "%s-dag-processor" (include "airflow.serviceAccountName" .)) .Values.dagProcessor.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.dagProcessor.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the pgbouncer service account to use */}}
{{- define "pgbouncer.serviceAccountName" -}}
  {{- if .Values.pgbouncer.serviceAccount.create }}
    {{- default (printf "%s-pgbouncer" (include "airflow.serviceAccountName" .)) .Values.pgbouncer.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.pgbouncer.serviceAccount.name }}
  {{- end }}
{{- end }}

{{/* Create the name of the cleanup service account to use */}}
{{- define "cleanup.serviceAccountName" -}}
  {{- if .Values.cleanup.serviceAccount.create }}
    {{- default (printf "%s-cleanup" (include "airflow.serviceAccountName" .)) .Values.cleanup.serviceAccount.name }}
  {{- else }}
    {{- default "default" .Values.cleanup.serviceAccount.name }}
  {{- end }}
{{- end }}

{{- define "wait-for-migrations-command" -}}
  {{- if semverCompare ">=2.0.0" .Values.airflowVersion }}
  - airflow
  - db
  - check-migrations
  - --migration-wait-timeout={{ .Values.images.migrationsWaitTimeout }}
  {{- else }}
  - python
  - -c
  - |
        import airflow
        import logging
        import os
        import time

        from alembic.config import Config
        from alembic.runtime.migration import MigrationContext
        from alembic.script import ScriptDirectory

        from airflow import settings

        package_dir = os.path.abspath(os.path.dirname(airflow.__file__))
        directory = os.path.join(package_dir, 'migrations')
        config = Config(os.path.join(package_dir, 'alembic.ini'))
        config.set_main_option('script_location', directory)
        config.set_main_option('sqlalchemy.url', settings.SQL_ALCHEMY_CONN.replace('%', '%%'))
        script_ = ScriptDirectory.from_config(config)

        timeout=60

        with settings.engine.connect() as connection:
            context = MigrationContext.configure(connection)
            ticker = 0
            while True:
                source_heads = set(script_.get_heads())

                db_heads = set(context.get_current_heads())
                if source_heads == db_heads:
                    break

                if ticker >= timeout:
                    raise TimeoutError("There are still unapplied migrations after {} seconds.".format(ticker))
                ticker += 1
                time.sleep(1)
                logging.info('Waiting for migrations... %s second(s)', ticker)
  {{- end }}
{{- end }}

{{- define "scheduler_liveness_check_command" }}
  {{- if semverCompare ">=2.5.0" .Values.airflowVersion }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type SchedulerJob --local
  {{- else if semverCompare ">=2.1.0" .Values.airflowVersion }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type SchedulerJob --hostname $(hostname)
  {{- else }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 exec /entrypoint python -Wignore -c "
    import os
    os.environ['AIRFLOW__CORE__LOGGING_LEVEL'] = 'ERROR'
    os.environ['AIRFLOW__LOGGING__LOGGING_LEVEL'] = 'ERROR'
    from airflow.jobs.scheduler_job import SchedulerJob
    from airflow.utils.db import create_session
    from airflow.utils.net import get_hostname
    import sys
    with create_session() as session:
        job = session.query(SchedulerJob).filter_by(hostname=get_hostname()).order_by(
            SchedulerJob.latest_heartbeat.desc()).limit(1).first()
    sys.exit(0 if job.is_alive() else 1)"
  {{- end }}
{{- end }}


{{- define  "scheduler_startup_check_command" }}
  {{- if semverCompare ">=2.5.0" .Values.airflowVersion }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type SchedulerJob --local
  {{- else if semverCompare ">=2.1.0" .Values.airflowVersion }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type SchedulerJob --hostname $(hostname)
  {{- else }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 exec /entrypoint python -Wignore -c "
    import os
    os.environ['AIRFLOW__CORE__LOGGING_LEVEL'] = 'ERROR'
    os.environ['AIRFLOW__LOGGING__LOGGING_LEVEL'] = 'ERROR'
    from airflow.jobs.scheduler_job import SchedulerJob
    from airflow.utils.db import create_session
    from airflow.utils.net import get_hostname
    import sys
    with create_session() as session:
        job = session.query(SchedulerJob).filter_by(hostname=get_hostname()).order_by(
            SchedulerJob.latest_heartbeat.desc()).limit(1).first()
    sys.exit(0 if job.is_alive() else 1)"
  {{- end }}
{{- end }}

{{- define "triggerer_liveness_check_command" }}
  {{- if semverCompare ">=2.5.0" .Values.airflowVersion }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type TriggererJob --local
  {{- else }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check --job-type TriggererJob --hostname $(hostname)
  {{- end }}
{{- end }}

{{- define "dag_processor_liveness_check_command" }}
  {{- $commandArgs := (list) -}}
  {{- if semverCompare ">=2.5.0" .Values.airflowVersion }}
    {{- $commandArgs = append $commandArgs "--local" -}}
    {{- if semverCompare ">=2.5.2" .Values.airflowVersion }}
      {{- $commandArgs = concat $commandArgs (list "--job-type" "DagProcessorJob") -}}
    {{- end }}
  {{- else }}
    {{- $commandArgs = concat $commandArgs (list "--hostname" "$(hostname)") -}}
  {{- end }}
  - sh
  - -c
  - |
    CONNECTION_CHECK_MAX_COUNT=0 AIRFLOW__LOGGING__LOGGING_LEVEL=ERROR exec /entrypoint \
    airflow jobs check {{ join " " $commandArgs }}
{{- end }}

{{- define "registry_docker_config" }}
  {{- $host := .Values.registry.connection.host }}
  {{- $email := .Values.registry.connection.email }}
  {{- $user := .Values.registry.connection.user }}
  {{- $pass := .Values.registry.connection.pass }}

  {{- $config := dict "auths" }}
  {{- $auth := dict }}
  {{- $data := dict }}
  {{- $_ := set $data "username" $user }}
  {{- $_ := set $data "password" $pass }}
  {{- $_ := set $data "email" $email }}
  {{- $_ := set $data "auth" (printf "%v:%v" $user $pass | b64enc) }}
  {{- $_ := set $auth $host $data }}
  {{- $_ := set $config "auths" $auth }}
  {{ $config | toJson | print }}
{{- end }}

{{/*
Set the default value for pod securityContext
If no value is passed for securityContexts.pod or <node>.securityContexts.pod or legacy securityContext and <node>.securityContext, defaults to global uid and gid.

    +-----------------------------+      +------------------------+      +----------------------+      +-----------------+      +-------------------------+
    | <node>.securityContexts.pod |  ->  | <node>.securityContext |  ->  | securityContexts.pod |  ->  | securityContext |  ->  | Values.uid + Values.gid |
    +-----------------------------+      +------------------------+      +----------------------+      +-----------------+      +-------------------------+

Values are not accumulated meaning that if runAsUser is set to 10 in <node>.securityContexts.pod,
any extra values set to securityContext or uid+gid will be ignored.

The template can be called like so:
   include "airflowPodSecurityContext" (list . .Values.webserver)

Where `.` is the global variables scope and `.Values.webserver` the local variables scope for the webserver template.
*/}}
{{- define "airflowPodSecurityContext" -}}
  {{- $ := index . 0 -}}
  {{- with index . 1 }}
    {{- if .securityContexts.pod -}}
      {{ toYaml .securityContexts.pod | print }}
    {{- else if .securityContext -}}
      {{ toYaml .securityContext | print }}
    {{- else if $.Values.securityContexts.pod -}}
      {{ toYaml $.Values.securityContexts.pod | print }}
    {{- else if $.Values.securityContext -}}
      {{ toYaml $.Values.securityContext | print }}
    {{- else -}}
runAsUser: {{ $.Values.uid }}
fsGroup: {{ $.Values.gid }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Set the default value for pod securityContext
If no value is passed for <node>.securityContexts.pod or <node>.securityContext, defaults to UID in the local node.

    +-----------------------------+      +------------------------+      +-------------+
    | <node>.securityContexts.pod |  ->  | <node>.securityContext |  ->  | <node>.uid  |
    +-----------------------------+      +------------------------+      +-------------+

The template can be called like so:
  include "localPodSecurityContext" (list . .Values.schedule)

It is important to pass the local variables scope to this template as it is used to determine the local node value for uid.
*/}}
{{- define "localPodSecurityContext" -}}
  {{- if .securityContexts.pod -}}
    {{ toYaml .securityContexts.pod | print }}
  {{- else if .securityContext -}}
    {{ toYaml .securityContext | print }}
  {{- else -}}
runAsUser: {{ .uid }}
  {{- end -}}
{{- end -}}

{{/*
Set the default value for container securityContext
If no value is passed for <node>.securityContexts.container or <node>.securityContext, defaults to UID in the local node.

    +-----------------------------------+      +------------------------+      +-------------+
    | <node>.securityContexts.container |  ->  | <node>.securityContext |  ->  | <node>.uid  |
    +-----------------------------------+      +------------------------+      +-------------+

The template can be called like so:
  include "localContainerSecurityContext" .Values.statsd

It is important to pass the local variables scope to this template as it is used to determine the local node value for uid.
*/}}
{{- define "localContainerSecurityContext" -}}
  {{- if .securityContexts.container -}}
    {{ toYaml .securityContexts.container | print }}
  {{- else if .securityContext -}}
    {{ toYaml .securityContext | print }}
  {{- else -}}
runAsUser: {{ .uid }}
  {{- end -}}
{{- end -}}

{{/*
Set the default value for workers chown for persistent storage
If no value is passed for securityContexts.pod or <node>.securityContexts.pod or legacy securityContext and <node>.securityContext, defaults to global uid and gid.
The template looks for `runAsUser` and `fsGroup` specifically, any other parameter will be ignored.

    +-----------------------------+      +----------------------------------------------------+      +------------------+      +-------------------------+
    | <node>.securityContexts.pod |  ->  | securityContexts.pod | <node>.securityContexts.pod |  ->  | securityContexts |  ->  | Values.uid + Values.gid |
    +-----------------------------+      +----------------------------------------------------+      +------------------+      +-------------------------+

Values are not accumulated meaning that if runAsUser is set to 10 in <node>.securityContexts.pod,
any extra values set to securityContexts or uid+gid will be ignored.

The template can be called like so:
   include "airflowPodSecurityContextsIds" (list . .Values.webserver)

Where `.` is the global variables scope and `.Values.workers` the local variables scope for the workers template.
*/}}
{{- define "airflowPodSecurityContextsIds" -}}
  {{- $ := index . 0 -}}
  {{- with index . 1 }}
    {{- if .securityContexts.pod -}}
      {{ pluck "runAsUser" .securityContexts.pod | first | default $.Values.uid }}:{{ pluck "fsGroup" .securityContexts.pod | first | default $.Values.gid }}
    {{- else if $.Values.securityContext -}}
      {{ pluck "runAsUser" $.Values.securityContext | first | default $.Values.uid }}:{{ pluck "fsGroup" $.Values.securityContext | first | default $.Values.gid }}
    {{- else if $.Values.securityContexts.pod -}}
      {{ pluck "runAsUser" $.Values.securityContexts.pod | first | default $.Values.uid }}:{{ pluck "fsGroup" $.Values.securityContexts.pod | first | default $.Values.gid }}
    {{- else if $.Values.securityContext -}}
      {{ pluck "runAsUser" $.Values.securityContext | first | default $.Values.uid }}:{{ pluck "fsGroup" $.Values.securityContext | first | default $.Values.gid }}
    {{- else -}}
{{ $.Values.uid }}:{{ $.Values.gid }}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Set the default value for container securityContext
If no value is passed for securityContexts.container or <node>.securityContexts.container, defaults to deny privileges escallation and dropping all POSIX capabilities.

    +-----------------------------------+      +----------------------------+      +-----------------------------------------------------------+
    | <node>.securityContexts.container |  ->  | securityContexts.containers |  ->  | allowPrivilegesEscalation: false, capabilities.drop: [ALL]|
    +-----------------------------------+      +----------------------------+      +-----------------------------------------------------------+

The template can be called like so:
   include "containerSecurityContext" (list . .Values.webserver)

Where `.` is the global variables scope and `.Values.webserver` the local variables scope for the webserver template.
*/}}
{{- define "containerSecurityContext" -}}
  {{- $ := index . 0 -}}
  {{- with index . 1 }}
    {{- if .securityContexts.container -}}
      {{ toYaml .securityContexts.container | print }}
    {{- else if $.Values.securityContexts.containers -}}
      {{ toYaml $.Values.securityContexts.containers | print }}
    {{- else -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Set the default value for external container securityContext(redis and statsd).
If no value is passed for <node>.securityContexts.container, defaults to deny privileges escallation and dropping all POSIX capabilities.

    +-----------------------------------+      +-----------------------------------------------------------+
    | <node>.securityContexts.container |  ->  | allowPrivilegesEscalation: false, capabilities.drop: [ALL]|
    +-----------------------------------+      +-----------------------------------------------------------+

The template can be called like so:
  include "externalContainerSecurityContext" .Values.statsd
*/}}
{{- define "externalContainerSecurityContext" -}}
  {{- if .securityContexts.container -}}
    {{ toYaml .securityContexts.container | print }}
  {{- else -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
    - ALL
  {{- end -}}
{{- end -}}

{{- define "container_extra_envs" -}}
  {{- $ := index . 0 -}}
  {{- $env := index . 1 -}}
  {{- range $i, $config := $env }}
  - name: {{ $config.name }}
    {{- if $config.value }}
    value: {{ $config.value | quote }}
    {{- else if $config.valueFrom }}
    valueFrom:
      {{- if $config.valueFrom.secretKeyRef }}
      secretKeyRef:
        name: {{ $config.valueFrom.secretKeyRef.name }}
        key: {{ $config.valueFrom.secretKeyRef.key }}
      {{- else if $config.valueFrom.configMapKeyRef }}
      configMapKeyRef:
        name: {{ $config.valueFrom.configMapKeyRef.name }}
        key: {{ $config.valueFrom.configMapKeyRef.key }}
      {{- end }}
    {{- end }}
    {{- if or (eq $.Values.executor "KubernetesExecutor") (eq $.Values.executor "LocalKubernetesExecutor") (eq $.Values.executor "CeleryKubernetesExecutor") }}
  - name: AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__{{ $config.name }}
    {{- if $config.value }}
    value: {{ $config.value | quote }}
    {{- else if $config.valueFrom }}
    valueFrom:
      {{- if $config.valueFrom.secretKeyRef }}
      secretKeyRef:
        name: {{ $config.valueFrom.secretKeyRef.name }}
        key: {{ $config.valueFrom.secretKeyRef.key }}
      {{- else if $config.valueFrom.configMapKeyRef }}
      configMapKeyRef:
        name: {{ $config.valueFrom.configMapKeyRef.name }}
        key: {{ $config.valueFrom.configMapKeyRef.key }}
      {{- end }}
    {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "kedaNetworkPolicySelector" }}
  {{- if .Values.workers.keda.enabled }}

  {{- if .Values.workers.keda.namespaceLabels }}
      - namespaceSelector:
          matchLabels: {{- toYaml .Values.workers.keda.namespaceLabels | nindent 10 }}
        podSelector:
  {{- else }}
      - podSelector:
  {{- end }}
          matchLabels:
            app: keda-operator
  {{- end }}
{{- end }}