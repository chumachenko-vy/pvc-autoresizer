# PVC Autoresizer

Automatic PVC resize for Kubernetes clusters (GKE, Scaleway) with K8s >= 1.34.

## Problem

Kubernetes 1.34+ has a bug — kubelet does not export `kubelet_volume_stats_*` metrics via `/metrics` endpoint.
This chart provides a workaround using `kubelet-volume-stats-exporter` DaemonSet.

## Components

| Component | Description |
|-----------|-------------|
| **pvc-autoresizer** | Controller that monitors PVC usage via Prometheus and auto-resizes when threshold reached |
| **kubelet-volume-stats-exporter** | DaemonSet that reads `/stats/summary` from kubelet and exposes volume metrics |
| **CronJob annotator** | Every 5 min finds all Bound PVCs and sets `storage_limit` annotation |
| **PrometheusRule** | Alerts when PVC approaches storage limit (warning) or <10% free space (critical) |
| **ResourceQuota** | Allows exporter pods with `system-node-critical` priority class |

## Chain

```
kubelet /stats/summary → kubelet-volume-stats-exporter → Prometheus → pvc-autoresizer → resize PVC
```

## Prerequisites

- Kubernetes >= 1.34
- Prometheus (kube-prometheus-stack) with ServiceMonitor support
- cert-manager (required by pvc-autoresizer webhook)
- StorageClass with `allowVolumeExpansion: true`

## One-time manual steps (per cluster)

```bash
# Annotate StorageClasses
kubectl annotate sc <SC_NAME> resize.topolvm.io/enabled=true
```

## Deploy with ArgoCD

See `examples/argocd-application.yaml` for a ready ArgoCD Application manifest.

```bash
kubectl apply -f examples/argocd-application.yaml
```

## Deploy with Helm

```bash
cd pvc-autoresizer
helm dependency update
helm install pvc-autoresizer . -n pvc-autoresizer --create-namespace
```

## Configuration

Key values in `pvc-autoresizer/values.yaml`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `annotator.storageLimit` | `500Gi` | Max PVC size limit |
| `annotator.threshold` | `10%` | Usage threshold to trigger resize |
| `annotator.increase` | `10%` | How much to increase PVC size |
| `annotator.schedule` | `*/5 * * * *` | CronJob schedule |
| `autoresizer.controller.args.prometheusURL` | `http://prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local:9090` | Prometheus URL |
| `exporter.config.metricsPort` | `9118` | Exporter metrics port (9118 to avoid conflict with autoresizer on 8080) |
| `exporter.config.scrapeInterval` | `60s` | How often exporter scrapes kubelet (60s to avoid timeouts on busy nodes) |

## Known issues

- **kubelet-volume-stats-exporter image is amd64 only** — on mixed arch clusters add `exporter.nodeSelector.kubernetes.io/arch: amd64`
- **Busy nodes may cause exporter timeouts** — `scrapeInterval: 60s` helps; upstream exporter has no `--timeout` flag
- **PVCs without running pods have no metrics** — this is normal, autoresizer cannot monitor them but disks don't fill up without a running workload
