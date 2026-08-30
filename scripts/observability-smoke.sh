#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env.observability}"
ENV_EXAMPLE_FILE="${ROOT_DIR}/.env.observability.example"
COMPOSE_FILE="${ROOT_DIR}/compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-nitrogen-observability}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DOCKER_DESKTOP_BIN="/Applications/Docker.app/Contents/Resources/bin"

if [[ "${ENV_FILE}" != /* ]]; then
  ENV_FILE="${ROOT_DIR}/${ENV_FILE}"
fi

if [[ -d "${DOCKER_DESKTOP_BIN}" ]]; then
  PATH="${DOCKER_DESKTOP_BIN}:${PATH}"
  export PATH
fi

if ! command -v "${DOCKER_BIN}" >/dev/null 2>&1 && [[ -x /usr/local/bin/docker ]]; then
  DOCKER_BIN="/usr/local/bin/docker"
fi

if ! command -v "${DOCKER_BIN}" >/dev/null 2>&1 && [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
fi

compose() {
  local env_file="${ENV_FILE}"
  if [[ ! -f "${env_file}" ]]; then
    env_file="${ENV_EXAMPLE_FILE}"
  fi

  "${DOCKER_BIN}" compose \
    --env-file "${env_file}" \
    -f "${COMPOSE_FILE}" \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    "$@"
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1 && [[ ! -x "${DOCKER_BIN}" ]]; then
    echo "Docker CLI is required." >&2
    exit 1
  fi

  "${DOCKER_BIN}" compose version >/dev/null
  if ! "${DOCKER_BIN}" info >/dev/null 2>&1; then
    if [[ -z "${DOCKER_CONTEXT:-}" && -z "${DOCKER_HOST:-}" ]] \
        && "${DOCKER_BIN}" context inspect desktop-linux >/dev/null 2>&1 \
        && DOCKER_CONTEXT=desktop-linux "${DOCKER_BIN}" info >/dev/null 2>&1; then
      export DOCKER_CONTEXT=desktop-linux
      return
    fi

    "${DOCKER_BIN}" info >/dev/null
  fi
}

ensure_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required for observability smoke checks." >&2
    exit 1
  fi
}

load_env_file() {
  local env_file="${ENV_FILE}"
  if [[ ! -f "${env_file}" ]]; then
    env_file="${ENV_EXAMPLE_FILE}"
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    if [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -z "${!key+x}" ]]; then
      export "${key}=${value}"
    fi
  done < "${env_file}"
}

retry_until() {
  local label="$1"
  local timeout_seconds="$2"
  shift 2

  local deadline=$((SECONDS + timeout_seconds))
  until "$@"; do
    if (( SECONDS >= deadline )); then
      echo "${label} failed after ${timeout_seconds}s." >&2
      return 1
    fi
    sleep 2
  done

  echo "${label} OK"
}

http_contains() {
  local url="$1"
  local expected="$2"

  curl -fsS "${url}" | grep -Fq "${expected}"
}

prometheus_scrapes_backend() {
  local body
  body="$(curl -fsS -G \
    --data-urlencode 'query=up{job="nitrogen-backend"}' \
    "${PROMETHEUS_URL}/api/v1/query")"

  grep -Fq '"status":"success"' <<< "${body}" && grep -Fq '"1"' <<< "${body}"
}

grafana_health_ok() {
  local body
  body="$(curl -fsS "${GRAFANA_URL}/api/health")"

  grep -Fq '"database"' <<< "${body}" && grep -Fq '"ok"' <<< "${body}"
}

loki_contains_correlation() {
  local query
  local start_seconds
  local end_seconds
  local body
  query="{job=\"docker\"} |= \"${CORRELATION_ID}\""
  end_seconds="$(date +%s)"
  start_seconds=$((end_seconds - 600))
  body="$(curl -fsS -G \
    --data-urlencode "query=${query}" \
    --data-urlencode "start=${start_seconds}000000000" \
    --data-urlencode "end=${end_seconds}000000000" \
    --data-urlencode "limit=100" \
    "${LOKI_URL}/loki/api/v1/query_range")"

  grep -Fq "${CORRELATION_ID}" <<< "${body}"
}

docker_backend_log_contains_correlation() {
  "${DOCKER_BIN}" logs nitrogen-local-backend-web-1 --since 10m 2>&1 | grep -Fq "${CORRELATION_ID}"
}

tempo_received_trace() {
  curl -fsS "${TEMPO_URL}/metrics" \
    | grep -E 'tempo_distributor_spans_received_total.* [1-9][0-9]*(\.[0-9]+)?$' >/dev/null
}

ensure_docker
ensure_curl
load_env_file

BACKEND_URL="${NITROGEN_BACKEND_URL:-http://localhost:8080}"
PROMETHEUS_URL="http://localhost:${NITROGEN_PROMETHEUS_PORT:-9090}"
GRAFANA_URL="http://localhost:${NITROGEN_GRAFANA_PORT:-3000}"
LOKI_URL="http://localhost:${NITROGEN_LOKI_PORT:-3100}"
TEMPO_URL="http://localhost:${NITROGEN_TEMPO_PORT:-3200}"
OTEL_HEALTH_URL="http://localhost:${NITROGEN_OTEL_HEALTH_PORT:-13133}"
CORRELATION_ID="${NITROGEN_SMOKE_CORRELATION_ID:-smoke-$(date +%s)}"

retry_until "Backend liveness" 120 http_contains "${BACKEND_URL}/actuator/health/liveness" '"status":"UP"'
retry_until "Backend readiness" 120 http_contains "${BACKEND_URL}/actuator/health/readiness" '"status":"UP"'
retry_until "Backend Prometheus metrics" 120 http_contains "${BACKEND_URL}/actuator/prometheus" "jvm_"
retry_until "Prometheus ready" 120 http_contains "${PROMETHEUS_URL}/-/ready" "Prometheus Server is Ready"
retry_until "Prometheus backend scrape" 120 prometheus_scrapes_backend
retry_until "Grafana health" 120 grafana_health_ok
retry_until "Loki ready" 120 http_contains "${LOKI_URL}/ready" "ready"
retry_until "Tempo ready" 120 http_contains "${TEMPO_URL}/ready" "ready"
retry_until "OpenTelemetry Collector ready" 120 http_contains "${OTEL_HEALTH_URL}/" "Server available"

headers="$(curl -fsS -D - -o /dev/null -H "X-Correlation-ID: ${CORRELATION_ID}" \
  "${BACKEND_URL}/actuator/health/liveness" | tr -d '\r')"
grep -Fq "X-Correlation-ID: ${CORRELATION_ID}" <<< "${headers}"
echo "Backend correlation response header OK"

retry_until "Backend Docker log correlation ID" 120 docker_backend_log_contains_correlation
retry_until "Loki correlation ID query" 120 loki_contains_correlation

if [[ "${NITROGEN_TRACING_ENABLED:-false}" == "true" || "${NITROGEN_TRACE_SMOKE_ENABLED:-false}" == "true" ]]; then
  retry_until "Tempo received trace" 180 tempo_received_trace
else
  echo "Tempo trace smoke skipped because tracing is disabled."
fi
