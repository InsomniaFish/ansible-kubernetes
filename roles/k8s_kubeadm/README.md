# k8s_kubeadm

K8s 控制面初始化与 worker 节点加入。

## 作用

**master（`tasks/master.yml`）：**
- 渲染 kubeadm init 配置
- `kubeadm init`
- 等待 API ready
- 部署 CNI（calico / flannel）
- 生成 join 命令

**nodes（`tasks/nodes.yml`）：**
- 使用 master 生成的 join 命令执行 `kubeadm join`

## 执行范围

- master：`k8s_master`
- join：`k8s_nodes`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `kubeadm_kubernetes_version` | `1.34.8` | 集群版本 |
| `kubeadm_image_repository` | `registry.aliyuncs.com/google_containers` | 控制面镜像仓库 |
| `k8s_network_plugin` | `calico` | `calico` 或 `flannel` |
| `kubeadm_kubeproxy_mode` | `ipvs` | kube-proxy 模式 |
| `k8s_join_ttl` | `24h` | join token 有效期 |

## 使用方式

```bash
# 随主流程（无独立 playbook）
ansible-playbook k8s-cluster.yaml \
  -e k8s_network_plugin=calico

ansible-playbook k8s-cluster.yaml \
  -e k8s_network_plugin=flannel
```

## 镜像

见 [images.txt](./images.txt)（含 calico / flannel 条件镜像）
