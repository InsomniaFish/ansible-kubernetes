## 项目目录

```text
.
├── ansible.cfg                 # Ansible 配置（inventory、SSH 等）
├── files/                      # 离线包与 manifest（calico、flannel、cri-dockerd.deb 等）
├── hosts.ini                   # Inventory
├── install_ansible.sh          # 安装 Ansible + sshpass
├── ssh-init.sh                 # 批量检查 SSH 连通性
├── gen_inventory.sh            # 生成 inventory
├── k8s-cluster.yaml            # 主入口：完整集群部署
├── k8s-init-only.yaml          # 仅节点初始化（不 init/join）
├── k8s-reset.yaml              # 单独清理集群
├── k8s-prometheus.yaml         # 单独部署监控栈
├── k8s-completion.yaml         # 单独安装 bash 补全
└── roles/                      # 各 role 详见下文，每个 role 含 images.txt
```

## 最短使用路径

```bash
cd /path/to/ansible-kubernetes

./install_ansible.sh
./ssh-init.sh

# 演练
ansible-playbook --check --diff k8s-cluster.yaml

# 部署集群（默认 docker + calico + K8s 1.34.8）
ansible-playbook k8s-cluster.yaml

# 重建已有集群
ansible-playbook k8s-cluster.yaml -e k8s_enable_reset=true

# 启用可选组件
ansible-playbook k8s-cluster.yaml \
  -e k8s_enable_nfs=true \
  -e k8s_enable_harbor=true \
  -e k8s_enable_wireshark=true \
  -e k8s_enable_prometheus=true \
  -e prometheusalert_feishu_webhook_url='https://open.feishu.cn/open-apis/bot/v2/hook/xxx'
```

---

## Roles 说明

每个 role 目录下均有 `images.txt`，列出所需容器镜像（无镜像的 role 标注为无）。

### k8s_init

**作用：** 所有节点 OS 初始化 + 容器运行时 + kubelet/kubeadm/kubectl + bash 补全（内嵌 k8s_completion）。

**执行范围：** `k8s_cluster`

**主要任务：**
- 关闭 swap、配置 sysctl/内核模块/chrony
- 安装 Docker 或 containerd
- 安装 cri-dockerd（docker 模式）
- 安装 K8s 组件（apt，默认渠道 v1.34）
- 可选触发 k8s_reset（`k8s_enable_reset=true`）

**关键变量（`roles/k8s_init/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_container_runtime` | `docker` | `docker` 或 `containerd` |
| `k8s_version_channel` | `v1.34` | K8s apt 渠道 |
| `k8s_enable_reset` | `false` | 初始化前是否清理 |

**单独执行：**
```bash
ansible-playbook k8s-init-only.yaml
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=containerd
```

**镜像：** 见 `roles/k8s_init/images.txt`

---

### k8s_reset

**作用：** 重建前清理（kubeadm reset、删除 CNI/数据目录、停止运行时）。

**执行范围：** `k8s_cluster`

**关键变量（`roles/k8s_reset/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_reset_remove_cni` | `true` | 删除 CNI 配置 |
| `k8s_reset_remove_k8s_data` | `true` | 删除 /etc/kubernetes 等 |
| `k8s_reset_flush_iptables` | `false` | 是否 flush iptables |
| `k8s_reset_flush_ipvs` | `false` | 是否 flush IPVS |

**单独执行：**
```bash
ansible-playbook k8s-reset.yaml
# 或在 k8s-cluster 中：-e k8s_enable_reset=true
```

**镜像：** 无容器镜像

---

### k8s_completion

**作用：** 安装 kubectl/kubeadm bash 补全（已内嵌于 k8s_init，也可单独执行）。

**执行范围：** `k8s_cluster`

**单独执行：**
```bash
ansible-playbook k8s-completion.yaml
```

**镜像：** 无容器镜像

---

### k8s_kubeadm

**作用：** master 执行 kubeadm init + 部署 CNI；worker 执行 kubeadm join。

**执行范围：** master → `k8s_master`；join → `k8s_nodes`

**关键变量（`roles/k8s_kubeadm/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `kubeadm_kubernetes_version` | `1.34.8` | 集群版本 |
| `kubeadm_image_repository` | `registry.aliyuncs.com/google_containers` | 控制面镜像仓库 |
| `k8s_network_plugin` | `calico` | `calico` 或 `flannel` |
| `kubeadm_kubeproxy_mode` | `ipvs` | kube-proxy 模式 |

**说明：** 随 `k8s-cluster.yaml` 执行，无独立 playbook。

**镜像：** 见 `roles/k8s_kubeadm/images.txt`（含 calico/flannel 条件镜像）

---

### k8s_nfs

**作用：** 部署 NFS 服务端/客户端 + nfs-subdir-external-provisioner 动态存储。

**执行范围：** server/client → `k8s_cluster`；provisioner → `k8s_master`

**开关：** `k8s_enable_nfs=true`

**关键变量（`roles/k8s_nfs/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `nfs_server_export_dir` | `/srv/nfs` | NFS 导出目录 |
| `nfs_storageclass_name` | `nfs-client` | StorageClass 名称 |
| `nfs_storageclass_default` | `true` | 设为默认 SC |

**镜像：** 见 `roles/k8s_nfs/images.txt`

---

### k8s_harbor

**作用：** 在 master01 部署 Harbor（Docker Compose，非 K8s Pod），并让所有节点信任该仓库。

**执行范围：** `k8s_master`（默认 master01）

**开关：** `k8s_enable_harbor=true`

**关键变量（`roles/k8s_harbor/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_harbor_version` | `2.10.2` | Harbor 版本 |
| `k8s_harbor_http_port` | `80` | HTTP 端口 |
| `k8s_harbor_admin_password` | `Harbor12345` | admin 密码 |

**镜像：** 见 `roles/k8s_harbor/images.txt`

---

### k8s_prometheus

**作用：** 在 K8s 内部署完整监控栈 + 飞书告警（PrometheusAlert）。

**组件：**
- Prometheus v3.11.3
- Alertmanager v0.32.1
- Grafana 12.0.2
- node-exporter v1.11.1（DaemonSet）
- kube-state-metrics v2.18.0
- PrometheusAlert v4.9.2（Alertmanager → 飞书）

**执行范围：** `k8s_master`

**开关：** `k8s_enable_prometheus=true`

**访问（NodePort，默认）：**

| 服务 | 地址 |
|---|---|
| Prometheus | `http://<节点IP>:30090` |
| Grafana | `http://<节点IP>:30030`（admin / admin123） |
| PrometheusAlert | `http://<节点IP>:30080`（prometheusalert / prometheusalert） |

**集群内 FQDN：**
```
http://prometheus.monitoring.svc.cluster.local:9090
http://prometheus-alert.monitoring.svc.cluster.local:8080
```

**飞书配置：**
```bash
ansible-playbook k8s-prometheus.yaml \
  -e prometheusalert_feishu_webhook_url='https://open.feishu.cn/open-apis/bot/v2/hook/xxx'
```

飞书机器人若开启**关键词校验**，告警内容须包含对应关键词。

**关键变量（`roles/k8s_prometheus/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `monitoring_namespace` | `monitoring` | 命名空间 |
| `prometheusalert_enable` | `true` | 启用 PrometheusAlert |
| `prometheusalert_feishu_webhook_url` | `""` | 飞书 Webhook（必填） |
| `prometheus_node_port` | `30090` | Prometheus NodePort |
| `grafana_node_port` | `30030` | Grafana NodePort |
| `prometheusalert_node_port` | `30080` | PrometheusAlert NodePort |

**单独执行：**
```bash
ansible-playbook k8s-prometheus.yaml
ansible-playbook k8s-cluster.yaml -e k8s_enable_prometheus=true
```

**镜像：** 见 `roles/k8s_prometheus/images.txt`

---

### k8s_install_wireshark

**作用：** 所有节点安装 tshark + Node.js + WireMCP（LLM 实时抓包分析）。

**执行范围：** `k8s_cluster`

**开关：** `k8s_enable_wireshark=true`

**关键变量（`roles/k8s_install_wireshark/defaults/main.yml`）：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `wiremcp_node_major` | `20` | Node.js 大版本 |
| `wiremcp_install_dir` | `/opt/WireMCP` | 安装路径 |

**Cursor MCP 配置：**
```json
{
  "mcpServers": {
    "wiremcp": {
      "command": "node",
      "args": ["/opt/WireMCP/index.js"]
    }
  }
}
```

**镜像：** 无容器镜像

---

## 运行时与网络插件

默认：`docker` + `calico`，K8s **v1.34.8**。

```bash
# docker + calico（默认）
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=docker \
  -e k8s_network_plugin=calico

# containerd + flannel
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=containerd \
  -e k8s_network_plugin=flannel
```

- `k8s_container_runtime`：`docker` 或 `containerd`
- `k8s_network_plugin`：`calico` 或 `flannel`
- flannel 默认 `podSubnet=10.244.0.0/16`

## 环境兼容性

- **Controller 已验证：** Ubuntu 22.04 LTS，Ansible 2.10.8
- **目标节点：** Ubuntu 22.04 / 24.04（docker 模式需对应代号 cri-dockerd deb，22.04=jammy）
- **架构：** 默认 amd64

## 部署验证

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl -n monitoring get pods          # 启用监控栈后
kubectl get storageclass                  # 启用 NFS 后
```

节点异常时：
```bash
journalctl -u kubelet -xe --no-pager | tail -200
```
