# k8s_nfs

NFS 服务端/客户端 + K8s 动态存储（nfs-subdir-external-provisioner）。

## 作用

- **server.yml**：在 `nfs_server` 分组节点安装 nfs-kernel-server、配置 exports
- **client.yml**：在 `nfs_clients` 分组节点安装 nfs-common
- **provisioner.yml**：在 master 部署 NFS Provisioner + StorageClass

## 执行范围

- server/client：`k8s_cluster`
- provisioner：`k8s_master`

## 开关

`k8s_enable_nfs=true`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `nfs_server_export_dir` | `/srv/nfs` | NFS 导出目录 |
| `nfs_storageclass_name` | `nfs-client` | StorageClass 名称 |
| `nfs_storageclass_default` | `true` | 设为默认 SC |
| `nfs_provisioner_namespace` | `nfs-provisioner` | Provisioner 命名空间 |

## 使用方式

```bash
ansible-playbook k8s-cluster.yaml -e k8s_enable_nfs=true
```

验证：

```bash
kubectl get storageclass
```

## 镜像

见 [images.txt](./images.txt)
