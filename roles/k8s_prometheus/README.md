# k8s_prometheus

K8s 集群监控栈 + 飞书告警（PrometheusAlert）。

## 组件

| 组件 | 版本 | 说明 |
|---|---|---|
| Prometheus | v3.11.3 | 指标采集与存储 |
| Alertmanager | v0.32.1 | 告警路由 |
| Grafana | 12.0.2 | 可视化 |
| node-exporter | v1.11.1 | 节点指标（DaemonSet） |
| kube-state-metrics | v2.18.0 | K8s 对象指标 |
| PrometheusAlert | v4.9.2 | Alertmanager → 飞书 |

## 执行范围

`k8s_master`

## 开关

`k8s_enable_prometheus=true`

## 访问（NodePort 默认）

| 服务 | 地址 |
|---|---|
| Prometheus | `http://<节点IP>:30090` |
| Grafana | `http://<节点IP>:30030`（admin / admin123） |
| PrometheusAlert | `http://<节点IP>:30080`（prometheusalert / prometheusalert） |

集群内 FQDN：

```
http://prometheus.monitoring.svc.cluster.local:9090
http://prometheus-alert.monitoring.svc.cluster.local:8080
```

## 飞书告警

1. 飞书群创建自定义机器人，获取 Webhook
2. 部署时传入 Webhook URL

```bash
ansible-playbook k8s-prometheus.yaml \
  -e prometheusalert_feishu_webhook_url='https://open.feishu.cn/open-apis/bot/v2/hook/xxx'
```

告警链路：`Prometheus → Alertmanager → PrometheusAlert → 飞书`

若飞书机器人开启**关键词校验**，消息须包含对应关键词。

## 告警测试

### 1. 飞书 Webhook（最底层）

```bash
curl -X POST 'https://open.feishu.cn/open-apis/bot/v2/hook/xxx' \
  -H 'Content-Type: application/json' \
  -d '{"msg_type":"text","content":{"text":"告警：飞书 Webhook 测试"}}'
```

成功返回 `StatusCode:0`。若报 `19024 Key Words Not Found`，消息中须包含机器人设置的关键词。

### 2. PrometheusAlert（跳过 Prometheus/Alertmanager）

```bash
curl -X POST 'http://<节点IP>:30080/prometheusalert?type=fs&tpl=prometheus-fs' \
  -H 'Content-Type: application/json' \
  -d '[
    {
      "labels": {"alertname": "TestAlert", "severity": "warning"},
      "annotations": {"summary": "告警：PrometheusAlert 直连测试"}
    }
  ]'
```

或在 UI `http://<节点IP>:30080` 登录后手动测试飞书通道。

### 3. Alertmanager → PrometheusAlert → 飞书

```bash
# 在 master 上执行（ClusterIP 服务）
curl -X POST "http://$(kubectl get svc alertmanager -n monitoring -o jsonpath='{.spec.clusterIP}'):9093/api/v2/alerts" \
  -H 'Content-Type: application/json' \
  -d '[
    {
      "labels": {"alertname": "TestAlert", "severity": "critical"},
      "annotations": {"summary": "告警：Alertmanager 链路测试"},
      "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "endsAt": "'$(date -u -d '+5 min' +%Y-%m-%dT%H:%M:%SZ)'"
    }
  ]'
```

查看 Alertmanager 当前告警：

```bash
curl -s "http://$(kubectl get svc alertmanager -n monitoring -o jsonpath='{.spec.clusterIP}'):9093/api/v2/alerts" | python3 -m json.tool
```

### 4. 查看链路日志

```bash
kubectl -n monitoring logs deploy/alertmanager --tail=50
kubectl -n monitoring logs deploy/prometheus-alert --tail=50
curl -s 'http://<节点IP>:30090/api/v1/alerts'
curl -s 'http://<节点IP>:30090/api/v1/rules' | python3 -m json.tool | head -40
```

### 5. Pod 异常告警（端到端）

```bash
# 创建测试 Pod 并删 Pod 模拟异常（CrashLoopBackOff 会触发 KubePodCrashLooping）
kubectl run alert-test --image=busybox --restart=Always -- sh -c 'exit 1'
# 等待 5~10 分钟后查看
curl -s 'http://<节点IP>:30090/api/v1/alerts'
kubectl -n monitoring logs deploy/prometheus-alert --tail=20
kubectl delete pod alert-test --force --grace-period=0
```

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `monitoring_namespace` | `monitoring` | 命名空间 |
| `prometheusalert_enable` | `true` | 启用 PrometheusAlert |
| `prometheusalert_feishu_webhook_url` | `""` | 飞书 Webhook |
| `prometheus_node_port` | `30090` | Prometheus NodePort |
| `grafana_node_port` | `30030` | Grafana NodePort |
| `prometheusalert_node_port` | `30080` | PrometheusAlert NodePort |
| `prometheus_alert_rules_enable` | `true` | 启用 K8s 告警规则 |
| `prometheus_alert_keyword_prefix` | `告警：` | 告警摘要前缀（适配飞书关键词） |

## 内置告警规则

| 告警 | 触发条件 |
|---|---|
| KubePodCrashLooping | 容器 CrashLoopBackOff 持续 5m |
| KubePodNotReady | Pod Failed/Unknown 持续 5m |
| KubePodPending | Pod Pending 超过 10m |
| KubeDeploymentReplicasMismatch | Deployment 副本不可用 10m |
| KubeNodeNotReady | 节点 NotReady 5m |
| KubeNodeMemoryPressure | 节点内存压力 5m |
| KubeNodeDiskPressure | 节点磁盘压力 5m |
| NodeFilesystemSpaceFillingUp | 节点磁盘使用率 > 90% |

## 使用方式

```bash
ansible-playbook k8s-prometheus.yaml
ansible-playbook k8s-cluster.yaml -e k8s_enable_prometheus=true
```

## 镜像

见 [images.txt](./images.txt)
