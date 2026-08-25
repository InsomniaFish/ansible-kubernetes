# k8s_metrics_server

部署 metrics-server，使 `kubectl top nodes` / `kubectl top pods` 可用。

## 组件

| 组件 | 版本 | 说明 |
|---|---|---|
| metrics-server | v0.8.0 | Metrics API（`metrics.k8s.io/v1beta1`） |

## 执行范围

`k8s_master`

## 开关

`k8s_enable_metrics_server=true`

## 关键变量（`defaults/main.yml`）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `metrics_server_version` | `v0.8.0` | 版本 |
| `metrics_server_image` | 阿里云镜像 | 默认国内源，可覆盖 |
| `metrics_server_kubelet_insecure_tls` | `true` | 跳过 kubelet 证书校验（自签集群建议开启） |
| `metrics_server_host_network` | `false` | Pod 网络不通 kubelet 时改宿主机网络 |

## 单独执行

```bash
ansible-playbook k8s-metrics-server.yaml
# 或在 k8s-cluster 中：-e k8s_enable_metrics_server=true
```

## 验证

```bash
kubectl top nodes
kubectl top pods -A
```

**镜像：** 见 `images.txt`
