## 目录结构与作用

```text
.
├── ansible.cfg                               # Ansible 项目级配置（默认 inventory=./hosts.ini、SSH 参数、关闭 host key 检查等）
├── files/                                    # controller 本地文件目录（离线/预下载/大文件），由 role 从这里分发到各节点
│   ├── calico.yaml                            # Calico CNI manifest（master 上会 kubectl apply）
│   ├── kube-flannel.yml                      # Flannel CNI manifest（如选择 flannel）
│   ├── cri-dockerd.deb                        # cri-dockerd 安装包（docker runtime 时由 k8s_init 分发到各节点安装）
│   └── nginx-podip/                           # 示例镜像目录（nginx 页面显示 PodIP）
│       ├── Dockerfile
│       ├── entrypoint.sh
│       └── default.conf
├── gen_inventory.sh                           # 生成 inventory 的脚本：用任意 master IP + nodes IP 生成一份 hosts.ini 风格文件
├── hosts.ini                                 # Inventory：定义 k8s_master/k8s_nodes/k8s_cluster + 登录账号密码（ansible_user/ansible_password）
├── install_ansible.sh                         # controller 侧安装 Ansible + sshpass（Ubuntu/Debian apt 方式）
├── k8s-cluster.yaml                           # 入口 playbook：k8s_init → NFS(可选) → Harbor(可选) → master init+CNI → nodes join → NFS 动态存储(可选)
├── k8s-init-only.yaml                         # 仅初始化与安装运行时（不做 kubeadm init / join）
├── k8s-reset.yaml                             # 单独执行重建清理
├── README.md                                 # 本说明文档（你正在看的这个文件）
├── roles/                                    # Ansible roles（把复杂逻辑拆分成可复用模块）
│   ├── k8s_init/                              # 角色：所有节点系统初始化 + 容器运行时 + kubelet/kubeadm/kubectl（可触发 reset）
│   │   ├── defaults/
│   │   │   └── main.yml                       # k8s_init 默认变量（sysctl/modules/docker 镜像加速/k8s 版本渠道/本地 deb 路径等）
│   │   ├── handlers/
│   │   │   └── main.yml                       # handlers：配置变更后需要重启/daemon-reload 的动作（docker/chrony/systemd-modules-load 等）
│   │   ├── tasks/
│   │   │   ├── containerd.yml                 # 安装/配置 containerd：添加 repo → 生成 config → systemd cgroup/pause 镜像
│   │   │   ├── cri-dockerd.yml                # 安装 cri-dockerd：从 files/ 分发 deb → apt 安装 → systemd override → 启动服务
│   │   │   ├── docker.yml                     # 安装/配置 Docker：添加 repo → 安装 docker-ce → 写 daemon.json → 启动服务
│   │   │   ├── kubernetes.yml                 # 安装 K8s 组件：添加 K8s repo → 安装 kubelet/kubeadm/kubectl（按渠道选择版本）
│   │   │   ├── main.yml                       # k8s_init 任务入口：根据 k8s_container_runtime 选择 docker/containerd
│   │   │   └── system.yml                     # OS 初始化：hosts/swap/chrony/limits/modules/sysctl 等（尽量幂等）
│   │   └── templates/
│   │       ├── chrony.conf.j2                 # chrony 配置模板（时间同步）
│   │       ├── daemon.json.j2                 # Docker daemon.json 模板（镜像加速/cgroupdriver/log 等）
│   │       └── sysctl-k8s.conf.j2             # K8s sysctl 模板（ip_forward/bridge-nf-call 等）
│   ├── k8s_reset/                             # 角色：重建前清理（kubeadm reset/CNI/数据目录/可选清理 iptables）
│   │   ├── defaults/
│   │   │   └── main.yml                       # k8s_reset 默认变量（是否清理 iptables/IPVS）
│   │   └── tasks/
│   │       └── main.yml                       # 重建清理任务入口
│   ├── k8s_completion/                        # 角色：kubectl/kubeadm bash 补全
│   │   └── tasks/
│   │       └── main.yml
│   ├── k8s_nfs/                               # 角色：部署 NFS（由 nfs_server/nfs_clients 分组决定）+ K8s 动态存储
│   │   ├── defaults/
│   │   │   └── main.yml                       # NFS 默认变量（导出目录/权限/StorageClass 等）
│   │   ├── tasks/
│   │   │   ├── client.yml                     # NFS 客户端：安装 nfs-common
│   │   │   ├── server.yml                     # NFS 服务器：安装 nfs-kernel-server、配置 /etc/exports
│   │   │   ├── provisioner.yml                # 部署 nfs-subdir-external-provisioner + StorageClass
│   │   │   └── main.yml                       # 任务入口：server.yml (master) + client.yml (all)
│   │   └── templates/
│   │       └── nfs-provisioner.yaml.j2        # NFS Provisioner 清单模板（Deployment/RBAC/StorageClass）
│   ├── k8s_kubeadm/                           # 角色：master kubeadm init + apply CNI + 生成 join 命令；nodes 执行 join
│   │   ├── defaults/
│   │   │   └── main.yml                       # k8s_kubeadm 默认变量（kubeadm 模板变量、CNI 选择与 manifest 路径、join ttl 等）
│   │   ├── tasks/
│   │   │   ├── master.yml                     # master 任务：渲染 kubeadm 配置 → kubeadm init → 等待 API ready → apply CNI → 生成 join 命令
│   │   │   └── nodes.yml                      # node 任务：判断是否已 join → kubeadm join（使用 master 生成的 join 命令）
│   │   └── templates/
│   │       └── kubeadm-init.yaml.j2           # kubeadm init 配置模板（advertiseAddress/版本/仓库/serviceSubnet/ipvs/cgroupDriver 等）
│   └── k8s_harbor/                            # 角色：在 master01 上部署 Harbor（不进 K8s），并让所有节点信任该仓库
│       ├── defaults/
│       │   └── main.yml                       # Harbor 默认变量（版本/目录/端口/账号密码/目标主机等）
│       ├── tasks/
│       │   └── main.yml                       # 安装 Harbor + 写入 insecure-registries + 重启 Docker
│       └── templates/
│           └── harbor.yml.j2                  # Harbor 配置模板
└── ssh-init.sh                                # 纯 bash 脚本：用 sshpass 批量检查 22 端口+SSH 密码登录是否正常（不依赖 ansible）
```

## 最短使用路径（建议）

```bash
cd /path/to/ansible-kubernetes

# 1) 安装 Ansible（controller）
./install_ansible.sh

# 2)（可选）先检查 SSH 密码登录是否都正常
./ssh-init.sh

# 3) 演练（只预览变更）
ansible-playbook --check --diff k8s-cluster.yaml

# 仅初始化与安装运行时（不做 kubeadm init / join）
ansible-playbook k8s-init-only.yaml

# 仅初始化：docker 运行时
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=docker

# 仅初始化：containerd 运行时
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=containerd

# 4) 正式执行（默认不启用 NFS）
ansible-playbook k8s-cluster.yaml

# 可选：启用 NFS 动态存储
ansible-playbook k8s-cluster.yaml -e k8s_enable_nfs=true

# 可选：重建前清理（k8s_init 内触发 k8s_reset）
ansible-playbook k8s-cluster.yaml -e k8s_enable_reset=true

# 可选：安装 Harbor（master01，非 K8s）
ansible-playbook k8s-cluster.yaml -e k8s_enable_harbor=true

# 单独执行重建清理
ansible-playbook k8s-reset.yaml
```

## 运行时与网络插件选择

默认：`docker` + `calico`，K8s 版本为 **v1.32**（`kubeadm_kubernetes_version=1.32.11`）。如需切换：

```bash
# 1) docker + calico（默认）
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=docker \
  -e k8s_network_plugin=calico

# 2) docker + flannel
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=docker \
  -e k8s_network_plugin=flannel

# 3) containerd + calico
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=containerd \
  -e k8s_network_plugin=calico

# 选择 containerd + flannel
ansible-playbook k8s-cluster.yaml \
  -e k8s_container_runtime=containerd \
  -e k8s_network_plugin=flannel
```

说明：
- `k8s_container_runtime` 仅支持 `docker` 或 `containerd`
- `k8s_network_plugin` 仅支持 `calico` 或 `flannel`
- 使用 `flannel` 时请准备 `files/kube-flannel.yml`（或通过变量指向自定义位置）
- 使用 `flannel` 时默认 `podSubnet=10.244.0.0/16`，如需调整可设置 `kubeadm_pod_subnet`

重建清理（可选，k8s_init 内触发 k8s_reset）：
- 启用：`-e k8s_enable_reset=true`
- 可选开关：`k8s_reset_flush_iptables`、`k8s_reset_flush_ipvs`

如需切换运行时/CNI，建议先清理再重建：
```bash
ansible-playbook k8s-reset.yaml
# 然后选择下面任意组合命令重新部署
```

仅安装运行时（不 init / join）：
```bash
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=docker
ansible-playbook k8s-init-only.yaml -e k8s_container_runtime=containerd
```

## 环境信息 / 兼容性

- **controller（本机）已验证**：
  - Ubuntu **22.04.5 LTS**（Jammy），kernel **5.15.0-168-generic**
  - Ansible **2.10.8**
- **目标机**：
  - 适配 **Ubuntu 22.04 / 24.04**（更高版本也可以；若选用 `docker` 运行时，`cri-dockerd` 的 deb 需要匹配发行版代号）
  - 需要能 SSH 登录（建议 SSH key；若用密码，需要安装 `sshpass`）

> 说明：本项目使用 `files/` 下的离线包（例如 `cri-dockerd.deb`）来避免运行时在线下载带来的不确定性。

## 部署完成后的效果（预期）与验证命令

当 `ansible-playbook k8s-cluster.yaml` 执行完成后，你可以在 master 上验证：

```bash
# 查看节点是否 Ready
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide

# 查看核心组件与 CNI 是否正常
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get pods

# 进一步确认 CNI 关键组件（可选）
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get ds calico-node
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get deploy calico-kube-controllers
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get ds kube-flannel-ds
```

验证 NFS 动态存储（StorageClass/PVC）（启用 NFS 后）：

```bash
# 查看默认 StorageClass 是否为 NFS
kubectl --kubeconfig /etc/kubernetes/admin.conf get storageclass

# 可选：创建一个测试 PVC
cat <<'EOF' | kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
EOF
```

如果节点未 Ready，优先看：

```bash
journalctl -u kubelet -xe --no-pager | tail -200
```


