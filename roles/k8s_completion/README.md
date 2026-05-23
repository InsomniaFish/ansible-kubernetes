# k8s_completion

安装 kubectl / kubeadm 的 bash 补全。

## 作用

- 安装 `bash-completion` 包
- 生成并写入 `/etc/bash_completion.d/kubectl`
- 生成并写入 `/etc/bash_completion.d/kubeadm`

## 执行范围

`k8s_cluster`

## 使用方式

```bash
# 已内嵌于 k8s_init，集群部署时自动执行

# 单独执行
ansible-playbook k8s-completion.yaml
```

新开终端或执行 `source /etc/profile.d/bash_completion.sh` 后，`kubectl <Tab>` 即可补全。

## 镜像

无容器镜像，见 [images.txt](./images.txt)
