## 目录结构与作用

```text
.
├── ansible.cfg                               # Ansible 项目级配置（默认 inventory=./hosts.ini、SSH 参数、关闭 host key 检查等）
├── files/                                    # controller 本地文件目录（离线/预下载/大文件），由 role 从这里分发到各节点
│   ├── calico.yaml                            # Calico CNI manifest（master 上会 kubectl apply）
│   └── cri-dockerd.deb                        # cri-dockerd 安装包（由 k8s_init 分发到各节点安装）
├── gen_inventory.sh                           # 生成 inventory 的脚本：用任意 master IP + nodes IP 生成一份 hosts.ini 风格文件
├── hosts.ini                                 # Inventory：定义 k8s_master/k8s_nodes/k8s_cluster + 登录账号密码（ansible_user/ansible_password）
├── install_ansible.sh                         # controller 侧安装 Ansible + sshpass（Ubuntu/Debian apt 方式）
├── k8s-cluster.yaml                           # 入口 playbook：全节点初始化(k8s_init) → master init+calico → nodes join
├── README.md                                 # 本说明文档（你正在看的这个文件）
├── roles/                                    # Ansible roles（把复杂逻辑拆分成可复用模块）
│   ├── k8s_init/                              # 角色：所有节点的系统初始化 + Docker + kubelet/kubeadm/kubectl + cri-dockerd
│   │   ├── defaults/
│   │   │   └── main.yml                       # k8s_init 默认变量（sysctl/modules/docker 镜像加速/k8s 版本渠道/本地 deb 路径等）
│   │   ├── handlers/
│   │   │   └── main.yml                       # handlers：配置变更后需要重启/daemon-reload 的动作（docker/chrony/systemd-modules-load 等）
│   │   ├── tasks/
│   │   │   ├── cri-dockerd.yml                # 安装 cri-dockerd：从 files/ 分发 deb → apt 安装 → systemd override → 启动服务
│   │   │   ├── docker.yml                     # 安装/配置 Docker：添加 repo → 安装 docker-ce → 写 daemon.json → 启动服务
│   │   │   ├── kubernetes.yml                 # 安装 K8s 组件：添加 K8s repo → 安装 kubelet/kubeadm/kubectl（按渠道选择版本）
│   │   │   ├── main.yml                       # k8s_init 任务入口：按顺序 include system.yml/docker.yml/kubernetes.yml/cri-dockerd.yml
│   │   │   └── system.yml                     # OS 初始化：hosts/swap/chrony/limits/modules/sysctl 等（尽量幂等）
│   │   └── templates/
│   │       ├── chrony.conf.j2                 # chrony 配置模板（时间同步）
│   │       ├── daemon.json.j2                 # Docker daemon.json 模板（镜像加速/cgroupdriver/log 等）
│   │       └── sysctl-k8s.conf.j2             # K8s sysctl 模板（ip_forward/bridge-nf-call 等）
│   └── k8s_kubeadm/                           # 角色：master kubeadm init + apply Calico + 生成 join 命令；nodes 执行 join
│       ├── defaults/
│       │   └── main.yml                       # k8s_kubeadm 默认变量（kubeadm 模板变量、calico manifest 路径、join ttl 等）
│       ├── tasks/
│       │   ├── master.yml                     # master 任务：渲染 kubeadm 配置 → kubeadm init → 等待 API ready → apply calico → 生成 join 命令
│       │   └── nodes.yml                      # node 任务：判断是否已 join → kubeadm join（使用 master 生成的 join 命令）
│       └── templates/
│           └── kubeadm-init.yaml.j2           # kubeadm init 配置模板（advertiseAddress/版本/仓库/serviceSubnet/ipvs/cgroupDriver 等）
└── ssh-init.sh                                # 纯 bash 脚本：用 sshpass 批量检查 22 端口+SSH 密码登录是否正常（不依赖 ansible）
```

## 最短使用路径（建议）

```bash
cd /root/ansible

# 1) 安装 Ansible（controller）
./install_ansible.sh

# 2)（可选）先检查 SSH 密码登录是否都正常
./ssh-init.sh

# 3) 演练（只预览变更）
ansible-playbook --check --diff k8s-cluster.yaml

# 4) 正式执行
ansible-playbook k8s-cluster.yaml
```

## 环境信息 / 兼容性

- **controller（本机）已验证**：
  - Ubuntu **22.04.5 LTS**（Jammy），kernel **5.15.0-168-generic**
  - Ansible **2.10.8**
- **目标机**：
  - 适配 **Ubuntu 22.04 / 24.04**（更高版本也可以，但 `cri-dockerd` 的 deb 需要匹配发行版代号）
  - 需要能 SSH 登录（建议 SSH key；若用密码，需要安装 `sshpass`）

> 说明：本项目使用 `files/` 下的离线包（例如 `cri-dockerd.deb`）来避免运行时在线下载带来的不确定性。

## 部署完成后的效果（预期）与验证命令

当 `ansible-playbook k8s-cluster.yaml` 执行完成后，你可以在 master 上验证：

```bash
# 查看节点是否 Ready
kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide

# 查看核心组件与 Calico 是否正常
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get pods

# 进一步确认 calico 关键组件（可选）
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get ds calico-node
kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get deploy calico-kube-controllers
```

如果节点未 Ready，优先看：

```bash
journalctl -u kubelet -xe --no-pager | tail -200
```


