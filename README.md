# PVC Autoresizer — ArgoCD Deployment

Автоматичне розширення PVC на GKE (Kubernetes 1.34+).

## Компоненти

| Компонент | Опис |
|-----------|------|
| cert-manager | TLS сертифікати для pvc-autoresizer webhook |
| kubelet-volume-stats-exporter | DaemonSet, який читає volume stats з kubelet і віддає в Prometheus |
| pvc-autoresizer | Контролер, який автоматично збільшує PVC при заповненні |

## Вимоги

- GKE кластер з Kubernetes >= 1.34
- Prometheus (kube-prometheus-stack) вже встановлений
- ArgoCD вже встановлений

## Деплой

```bash
kubectl apply -f argocd-apps/
```
