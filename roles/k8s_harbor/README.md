# k8s_harbor

在 master 节点部署 Harbor 私有镜像仓库（Docker Compose，非 K8s Pod）。

## 作用

- 下载并安装 Harbor 离线包
- 渲染 `harbor.yml` 并执行 `install.sh`
- 所有 K8s 节点 Docker 配置 `insecure-registries` 信任 Harbor

## 执行范围

`k8s_master`（默认 `master01`，由 `k8s_harbor_target_host` 指定）

## 开关

`k8s_enable_harbor=true`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `k8s_harbor_version` | `2.10.2` | Harbor 版本 |
| `k8s_harbor_install_dir` | `/opt/harbor` | 安装目录 |
| `k8s_harbor_http_port` | `80` | HTTP 端口 |
| `k8s_harbor_admin_password` | `Harbor12345` | admin 密码 |
| `k8s_harbor_target_host` | `master01` | 部署目标主机 |

## 使用方式

```bash
ansible-playbook k8s-cluster.yaml -e k8s_enable_harbor=true
```

访问：`http://<master-ip>/`（admin / Harbor12345）

## 镜像

见 [images.txt](./images.txt)（Harbor 离线包内置镜像）
