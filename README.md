# PVC Autoresizer

Автоматичне збільшення PVC на Kubernetes кластерах (GKE, Scaleway) з K8s >= 1.34.

## Проблема

Kubernetes 1.34+ має баг — kubelet не експортує `kubelet_volume_stats_*` метрики через `/metrics` endpoint ([kubernetes/kubernetes#133847](https://github.com/kubernetes/kubernetes/issues/133847)).
Без цих метрик неможливо моніторити заповнення дисків і автоматично їх збільшувати.

## Рішення

Цей Helm chart встановлює повний стек для автоматичного ресайзу PVC:

```
kubelet /stats/summary → kubelet-volume-stats-exporter → Prometheus → pvc-autoresizer → resize PVC
                                                                    → PrometheusRule → alerts
                                              CronJob annotator → PVC annotations (storage_limit)
```

## Компоненти

| Компонент | Що робить |
|-----------|-----------|
| [pvc-autoresizer](https://github.com/topolvm/pvc-autoresizer) | Контролер — моніторить PVC через Prometheus, збільшує коли заповнення досягає threshold |
| [kubelet-volume-stats-exporter](https://github.com/vbeaucha/kubelet-volume-stats-exporter) | DaemonSet — читає `/stats/summary` з kubelet і віддає метрики в Prometheus-форматі |
| CronJob annotator | Кожні 5 хв знаходить всі Bound PVC і ставить анотацію `storage_limit` (default: 500Gi) |
| PrometheusRule | Warning коли PVC наближається до ліміту (80%), Critical коли < 10% вільного місця |
| ResourceQuota | Дозволяє exporter поди з `system-node-critical` priority (потрібно на GKE) |

## Вимоги

- Kubernetes >= 1.34
- Prometheus (kube-prometheus-stack) з підтримкою ServiceMonitor
- cert-manager (потрібен для pvc-autoresizer webhook)
- StorageClass з `allowVolumeExpansion: true`

## Встановлення

```bash
cd pvc-autoresizer
helm dependency update
helm install pvc-autoresizer . \
  -n pvc-autoresizer \
  --create-namespace
```

Приклад ArgoCD Application для деплою через GitOps — в `examples/argocd-application.yaml`.

## Ручні кроки (один раз на кластер)

```bash
# Анотувати StorageClass (приклади для GKE та Scaleway)
kubectl annotate sc standard-rwo resize.topolvm.io/enabled=true   # GKE
kubectl annotate sc premium-rwo resize.topolvm.io/enabled=true    # GKE
kubectl annotate sc scw-bssd resize.topolvm.io/enabled=true       # Scaleway
kubectl annotate sc sbs-default resize.topolvm.io/enabled=true    # Scaleway
```

## Конфігурація

### Основні параметри (`values.yaml`)

| Параметр | Default | Опис |
|----------|---------|------|
| `annotator.storageLimit` | `500Gi` | Максимальний ліміт збільшення PVC |
| `annotator.threshold` | `10%` | При якому % використання починати ресайз |
| `annotator.increase` | `10%` | На скільки збільшувати PVC за раз |
| `annotator.schedule` | `*/5 * * * *` | Як часто CronJob перевіряє PVC |
| `alerts.enabled` | `true` | Увімкнути Prometheus алерти |
| `alerts.labels.release` | `prometheus` | Label для ServiceMonitor discovery |
| `resourceQuota.enabled` | `true` | Створити ResourceQuota для system-node-critical |

### Autoresizer

| Параметр | Default | Опис |
|----------|---------|------|
| `autoresizer.controller.args.prometheusURL` | `http://prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local:9090` | Prometheus endpoint |
| `autoresizer.controller.args.interval` | `10s` | Інтервал перевірки PVC |
| `autoresizer.controller.args.additionalArgs` | `["--no-annotation-check"]` | Працювати з будь-яким PVC без анотації на StorageClass |

### Exporter

| Параметр | Default | Опис |
|----------|---------|------|
| `exporter.config.metricsPort` | `9118` | Порт метрик (9118 замість 8080 — конфлікт з autoresizer) |
| `exporter.config.scrapeInterval` | `60s` | Інтервал збору метрик (60s для уникнення timeout на навантажених нодах) |
| `exporter.serviceMonitor.labels.release` | `prometheus` | Label для Prometheus discovery |

### Приклад override для кластера з arm64 нодами (GKE)

```yaml
exporter:
  nodeSelector:
    kubernetes.io/arch: amd64
```

## Як працює ресайз

1. **CronJob** кожні 5 хв ставить на всі Bound PVC анотації:
   - `resize.topolvm.io/storage_limit: 500Gi`
   - `resize.topolvm.io/threshold: 10%`
   - `resize.topolvm.io/increase: 10%`

2. **Exporter** (DaemonSet) на кожній ноді збирає метрики з kubelet `/stats/summary`

3. **Prometheus** скрейпить exporter через ServiceMonitor

4. **pvc-autoresizer** кожні 10 секунд перевіряє:
   - Якщо PVC заповнений на 90%+ → збільшує на 10%
   - Якщо PVC досяг `storage_limit` (500Gi) → зупиняється, логує `volume storage limit reached`

5. **PrometheusRule** генерує алерти:
   - `PVCStorageLimitReached` (warning) — PVC capacity >= 400Gi (80% від ліміту)
   - `PVCUsageCritical` (critical) — менше 10% вільного місця

## Тестування ресайзу

```bash
# 1. Створити тестовий PVC + Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-autoresize
  namespace: pvc-autoresizer
  annotations:
    resize.topolvm.io/storage_limit: 10Gi
    resize.topolvm.io/threshold: 50%
    resize.topolvm.io/increase: 1Gi
spec:
  accessModes: [ReadWriteOnce]
  volumeMode: Filesystem
  storageClassName: standard-rwo
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-autoresize-pod
  namespace: pvc-autoresizer
spec:
  containers:
    - name: writer
      image: busybox
      command: ["sh", "-c", "sleep infinity"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-autoresize
EOF

# 2. Зачекати 2 хвилини поки Prometheus підхопить метрики

# 3. Заповнити диск на 60% (threshold 50%)
kubectl exec -n pvc-autoresizer test-autoresize-pod -- dd if=/dev/zero of=/data/bigfile bs=1M count=600

# 4. Спостерігати — PVC має зрости з 1Gi до 2Gi за 1-2 хв
kubectl get pvc test-autoresize -n pvc-autoresizer -w

# 5. Після тесту — видалити
kubectl delete pod test-autoresize-pod -n pvc-autoresizer
kubectl delete pvc test-autoresize -n pvc-autoresizer
```

## Відомі обмеження

- **Exporter image тільки amd64** — на кластерах з arm64 нодами додайте `exporter.nodeSelector`
- **Timeout на навантажених нодах** — kubelet з великою кількістю подів може не встигати відповісти; `scrapeInterval: 60s` зменшує проблему
- **PVC без running подів** — не мають метрик, але диски й не заповнюються без workload
- **Kubernetes bug** — [kubernetes/kubernetes#133847](https://github.com/kubernetes/kubernetes/issues/133847), exporter потрібен поки баг не виправлять в upstream

## Перевірка після деплою

```bash
# Поди
kubectl get pods -n pvc-autoresizer

# CronJob
kubectl get cronjob -n pvc-autoresizer

# Метрики в Prometheus
kubectl port-forward -n prometheus svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090 → query: kubelet_volume_stats_available_bytes

# Алерти
# http://localhost:9090/alerts → PVCStorageLimitReached, PVCUsageCritical

# Логи autoresizer
kubectl logs -n pvc-autoresizer -l app.kubernetes.io/name=pvc-autoresizer-controller --tail=20

# Логи exporter
kubectl logs -n pvc-autoresizer <exporter-pod> --tail=10

# Логи CronJob
kubectl logs -n pvc-autoresizer -l app.kubernetes.io/name=pvc-autoresizer --tail=20
```
