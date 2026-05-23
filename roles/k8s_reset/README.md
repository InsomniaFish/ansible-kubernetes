# k8s_reset

重建 K8s 集群前的清理。

## 作用

- 停止 kubelet、docker、containerd、cri-docker
- 执行 `kubeadm reset -f`
- 删除 CNI 配置与 K8s 数据目录
- 可选 flush iptables / IPVS

## 执行范围

`k8s_cluster`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_reset_remove_cni` | `true` | 删除 /etc/cni/net.d 等 |
| `k8s_reset_remove_k8s_data` | `true` | 删除 /etc/kubernetes、/var/lib/kubelet 等 |
| `k8s_reset_remove_kubeconfig` | `true` | 删除 /root/.kube |
| `k8s_reset_flush_iptables` | `false` | flush iptables |
| `k8s_reset_flush_ipvs` | `false` | flush IPVS |

## 使用方式

```bash
# 单独清理
ansible-playbook k8s-reset.yaml

# 或在 k8s_init 内触发
ansible-playbook k8s-cluster.yaml -e k8s_enable_reset=true
```

## 镜像

无容器镜像，见 [images.txt](./images.txt)
