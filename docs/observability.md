# Observability

This repository owns the local/dev observability stack for Nitrogen. It is a
baseline for learning and development; production sizing and retention will be
revisited separately before Hetzner production rollout.

## Stack

Run the stack only when observability is needed:

```bash
cp .env.observability.example .env.observability
docker compose --env-file .env.observability --profile observability up -d
./scripts/observability-smoke.sh
```

The profile starts Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector,
and Grafana Alloy. Alloy reads Docker container logs and sends them to Loki.
Promtail is not used.

## Local URLs

| Service | URL |
|---|---|
| Grafana | `http://localhost:3000` |
| Prometheus | `http://localhost:9090` |
| Loki | `http://localhost:3100` |
| Tempo | `http://localhost:3200` |
| OTel Collector HTTP OTLP | `http://localhost:4318` |
| OTel Collector health | `http://localhost:13133` |
| Alloy | `http://localhost:12345` |

Grafana is provisioned with Prometheus, Loki, and Tempo datasources plus a
Nitrogen backend baseline dashboard. The example admin password is local-only;
do not reuse it outside a laptop stack.

## Retention

Defaults are intentionally small:

| Signal | Variable | Default |
|---|---|---|
| Metrics | `NITROGEN_PROMETHEUS_RETENTION` | `15d` |
| Logs | `NITROGEN_LOKI_RETENTION` | `168h` |
| Traces | `NITROGEN_TEMPO_RETENTION` | `72h` |

Override these in `.env.observability` when a dev machine needs shorter
retention.

## Log And Trace Correlation

Backend structured logs include `correlationId`, `traceId`, and `spanId`.
Grafana Loki derives trace links from `traceId`, and Tempo is configured with
trace-to-logs lookup against Loki.

The backend Docker compose file should send traces to:

```text
http://host.docker.internal:4318/v1/traces
```

The same application running directly on macOS should use:

```text
http://localhost:4318/v1/traces
```

## Smoke Test

`./scripts/observability-smoke.sh` checks:

| Check | Expected |
|---|---|
| Backend liveness/readiness | `UP` |
| Backend `/actuator/prometheus` | Contains JVM metrics |
| Prometheus target | `up{job="nitrogen-backend"} == 1` |
| Grafana | Healthy API response |
| Loki | Ready |
| Tempo | Ready |
| OTel Collector | Ready |
| Correlation ID | Request header is echoed |
| Logs | Correlation ID appears in Docker logs and Loki |
| Tracing | Tempo received spans when trace smoke is enabled |

To force trace smoke:

```bash
NITROGEN_TRACE_SMOKE_ENABLED=true ./scripts/observability-smoke.sh
```

## Troubleshooting

If Prometheus cannot scrape the backend, confirm the backend is running on
`http://localhost:8080` and that Docker can resolve `host.docker.internal`.

If Loki has no backend logs, confirm the backend is running through Docker
Compose project `nitrogen-local` and that Docker socket access is available to
Alloy.

If Tempo has no spans, confirm backend tracing is enabled and the backend uses
the OTLP HTTP endpoint visible from its runtime environment.
