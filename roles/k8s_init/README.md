# k8s_init

所有 K8s 节点的基础初始化：OS 调优、容器运行时、K8s 组件安装。

## 作用

- 配置 hosts、swap、sysctl、内核模块、chrony、limits
- 安装 Docker 或 containerd
- 安装 cri-dockerd（docker 模式）
- 安装 kubelet / kubeadm / kubectl（apt，默认 v1.34）
- 内嵌执行 `k8s_completion`
- 可选：初始化前触发 `k8s_reset`（`k8s_enable_reset=true`）

## 执行范围

`k8s_cluster`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_container_runtime` | `docker` | `docker` 或 `containerd` |
| `k8s_version_channel` | `v1.34` | K8s apt 渠道 |
| `k8s_enable_reset` | `false` | 初始化前是否清理 |
| `k8s_timezone` | `Asia/Shanghai` | 时区 |

## 使用方式

```bash
# 随主流程
ansible-playbook k8s-cluster.yaml

# 仅初始化（不 init/join）
ansible-playbook k8s-init-only.yaml
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=containerd

# 重建前清理并初始化
ansible-playbook k8s-cluster.yaml -e k8s_enable_reset=true
```

## 镜像

见 [images.txt](./images.txt)
