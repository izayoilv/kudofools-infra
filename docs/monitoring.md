# Monitoring & Logging

VictoriaMetrics stack on the rpi5 k3s cluster, managed by Flux from this repo.

## Components

| Component | Release / object | Version | Notes |
|---|---|---|---|
| VictoriaMetrics stack | HelmRelease `victoria-metrics` (release `monitoring-vm`) | chart `0.93.0`, VM `v1.152.0` | operator, VMSingle, VMAgent, VMAlert, Grafana, kube-state-metrics, node-exporter |
| VMSingle | `VMSingle/monitoring-vm-victoria-metrics-k8s-stack` | — | PVC 10Gi, retention **90d**, Prometheus-compatible API on `:8428` |
| VMAgent | `VMAgent/monitoring-vm-victoria-metrics-k8s-stack` | — | `selectAllByDefault`, 30s scrape, drops container port 8435 (dead reloader endpoints) |
| VMAlert | `VMAlert/monitoring-vm-victoria-metrics-k8s-stack` | — | 237 rules (chart defaults + our VMRules) |
| VMAlertmanager | `VMAlertmanager/monitoring-vm` | — | 1Gi PVC, routes to `matrix-alertmanager-receiver`, inhibits critical→warning |
| VictoriaLogs | HelmRelease `victoria-logs` (release `monitoring-vl`) | chart `0.13.9`, `v1.52.0` | PVC 10Gi, retention **30d**, 80% disk guard, LogsQL on `:9428` |
| vlagent | HelmRelease `vlagent` (release `monitoring-vlagent`) | chart `0.3.7` | DaemonSet, collects all container logs with Kubernetes metadata |
| Grafana | `monitoring-vm-grafana` | `13.1.1` | mesh-only at `grafana.kudofools.dev`; data sources: VictoriaMetrics (default), VictoriaLogs |

Alert rules live in `clusters/default/platform/monitoring-resources/vmrules.yaml`
(`kudofools.rpi`, `kudofools.flux`, `kudofools.certmanager`, `kudofools.targets`)
and as chart-default VMRules created by the stack's sync-job.

## Data flow

```
kubelet/KSM/node-exporter/apps ──► VMAgent ──► VMSingle ◄── VMAlert (rules)
containers ──► vlagent ──► VictoriaLogs
VMAlert ──► VMAlertmanager ──► matrix-alertmanager-receiver ──► Conduit ──► Matrix
Grafana ──► VMSingle / VictoriaLogs
```

## Querying

- Metrics (PromQL/MetricsQL), also used by Grafana:
  `kubectl -n monitoring port-forward svc/monitoring-vm-victoria-metrics-single-server 8428:8428`
  → `http://localhost:8428/` (vmui) or `/api/v1/query?query=up`
- Logs (LogsQL):
  `kubectl -n monitoring port-forward svc/monitoring-vl-victoria-logs-single-server 9428:9428`
  → `curl -X POST localhost:9428/select/logsql/query -d 'query=error' -d 'limit=10'`

## Operational notes

- The stack's sync-job fetches default rules and dashboards from GitHub at
  deploy time; they are not stored in this repo.
- The `monitoring` LimitRange caps containers at 1 CPU / 2Gi; VMSingle and
  Grafana run with 1536Mi limits.
- Grafana admin credentials come from the `grafana-secrets` ExternalSecret.
- The legacy kube-prometheus-stack, Loki and OTel collector were removed; the
  `monitoring.coreos.com` CRDs remain installed because the cert-manager chart
  still creates a ServiceMonitor (inert: the converter is disabled).
- Rollback: revert the cutover commit (`8025d5c`) and reconcile; old PVCs are
  kept for 24h after the cutover before cleanup.
