# Calico IPIP 模式 Pod 跨节点通信抓包分析

## 实验环境

### 集群信息
- **Kubernetes 版本**: v1.30+
- **CNI 插件**: Calico v3.31.3 (IPIP 模式)
- **节点配置**:
  - master01: 192.168.48.100
  - node01: 192.168.48.101
  - node02: 192.168.48.102

### 测试 Pod
```bash
# Pod 分布
NAME                    READY   STATUS    NODE     IP
network-tools-2-f5w5n   1/1     Running   node01   172.16.196.180
network-tools-2-zp6zj   1/1     Running   node02   172.16.140.81
```

### 网络拓扑
```
node01 (192.168.48.101)          node02 (192.168.48.102)
├─ Pod: 172.16.196.180           ├─ Pod: 172.16.140.81
├─ tunl0: 172.16.196.64/26       ├─ tunl0: 172.16.140.64/26
└─ ens33: 192.168.48.101         └─ ens33: 192.168.48.102
```

---

## 抓包准备

### 1. 安装 tshark

所有节点安装 tshark：
```bash
# Ubuntu/Debian
apt-get update && apt-get install -y tshark

# 或者使用 Ansible
ansible k8s_cluster -i hosts.ini -m apt -a "name=tshark,state=present,update_cache=yes"
```

### 2. 启动抓包

在所有节点上同时启动抓包，捕获 ens33 和 tunl0 接口的流量：

```bash
# 在 node01 和 node02 上执行
tshark -i ens33 -i tunl0 \
  -f "host 172.16.196.180 or host 172.16.140.81" \
  -a duration:40 \
  -T fields \
  -e frame.number \
  -e frame.time_relative \
  -e frame.interface_name \
  -e ip.src \
  -e ip.dst \
  -e ip.proto \
  -e icmp.type \
  -e icmp.code \
  -e frame.len \
  -e _ws.col.Info \
  -E header=y \
  -E separator='|' \
  2>/dev/null > /tmp/calico-ipip-capture.txt
```

**参数说明**：
- `-i ens33 -i tunl0`: 同时捕获物理接口和隧道接口
- `-f "host ..."`: BPF 过滤器，只捕获相关 Pod IP 的流量
- `-a duration:40`: 抓包 40 秒
- `-T fields`: 以字段形式输出
- `-e`: 指定要显示的字段
- `-E separator='|'`: 使用 `|` 分隔字段

### 3. 触发 Pod 通信

从源 Pod 向目标 Pod 发送 Ping 请求：

```bash
kubectl exec -n default network-tools-2-f5w5n -- ping -c 5 172.16.140.81
```

---

## 数据包分析

### 典型 ICMP 请求包示例

#### 1. tunl0 接口 - 封装前的原始 ICMP 包（node01）

```
frame.number|frame.time_relative|frame.interface_name|ip.src|ip.dst|ip.proto|icmp.type|icmp.code|frame.len|_ws.col.Info
1|0.000000000|tunl0|172.16.196.180|172.16.140.81|1|8|0|98|Echo (ping) request
```

**字段解析**：
- `frame.interface_name`: tunl0（隧道接口）
- `ip.src`: 172.16.196.180（源 Pod IP）
- `ip.dst`: 172.16.140.81（目标 Pod IP）
- `ip.proto`: 1（ICMP 协议）
- `icmp.type`: 8（Echo Request）
- `icmp.code`: 0
- `frame.len`: 98 字节
- `Info`: Echo (ping) request

#### 2. ens33 接口 - IPIP 封装后的包（node01）

```
frame.number|frame.time_relative|frame.interface_name|ip.src|ip.dst|ip.proto|frame.len|_ws.col.Info
2|0.000123456|ens33|192.168.48.101|192.168.48.102|4|126|IP encapsulation (IPIP)
```

**字段解析**：
- `frame.interface_name`: ens33（物理接口）
- `ip.src`: 192.168.48.101（node01 的物理 IP）
- `ip.dst`: 192.168.48.102（node02 的物理 IP）
- `ip.proto`: 4（IP-in-IP 封装协议）
- `frame.len`: 126 字节（外层 IP 头 20 字节 + 内层包 98 字节 + 以太网头 8 字节）
- `Info`: IP encapsulation (IPIP)

**IPIP 封装结构**：
```
┌─────────────────────────────────────────────────────────┐
│ 外层 IP 头 (20 字节)                                      │
│  Src: 192.168.48.101 (node01)                           │
│  Dst: 192.168.48.102 (node02)                           │
│  Proto: 4 (IPIP)                                        │
├─────────────────────────────────────────────────────────┤
│ 内层 IP 头 (20 字节)                                      │
│  Src: 172.16.196.180 (Pod A)                            │
│  Dst: 172.16.140.81 (Pod B)                             │
│  Proto: 1 (ICMP)                                        │
├─────────────────────────────────────────────────────────┤
│ ICMP 数据 (58 字节)                                       │
│  Type: 8 (Echo Request)                                 │
│  Code: 0                                                │
│  Data: ...                                              │
└─────────────────────────────────────────────────────────┘
```

#### 3. ens33 接口 - 接收 IPIP 包（node02）

```
frame.number|frame.time_relative|frame.interface_name|ip.src|ip.dst|ip.proto|frame.len|_ws.col.Info
3|0.001234567|ens33|192.168.48.101|192.168.48.102|4|126|IP encapsulation (IPIP)
```

**说明**：node02 的 ens33 接口收到 IPIP 封装包

#### 4. tunl0 接口 - 解封装后的 ICMP 包（node02）

```
frame.number|frame.time_relative|frame.interface_name|ip.src|ip.dst|ip.proto|icmp.type|icmp.code|frame.len|_ws.col.Info
4|0.001345678|tunl0|172.16.196.180|172.16.140.81|1|8|0|98|Echo (ping) request
```

**说明**：node02 的 tunl0 接口解封装后，露出原始 ICMP 包

#### 5. ICMP 响应包（反向路径）

```
# tunl0 - node02 发出响应
5|0.002000000|tunl0|172.16.140.81|172.16.196.180|1|0|0|98|Echo (ping) reply

# ens33 - IPIP 封装（node02 → node01）
6|0.002123456|ens33|192.168.48.102|192.168.48.101|4|126|IP encapsulation (IPIP)

# tunl0 - 解封装（node01）
7|0.003234567|tunl0|172.16.140.81|172.16.196.180|1|0|0|98|Echo (ping) reply
```

---

## 完整通信流程

### 步骤详解

```
┌──────────────────────────────────────────────────────────────────┐
│                    Calico IPIP 模式数据包传输流程                  │
└──────────────────────────────────────────────────────────────────┘

Step 1: 源 Pod 发出 ICMP 请求
┌─────────────────┐
│ Pod A           │
│ 172.16.196.180  │
│ node01          │
└────────┬────────┘
         │ ICMP Echo Request
         │ Src: 172.16.196.180
         │ Dst: 172.16.140.81
         ▼
┌─────────────────┐
│ cali* veth      │ ← Pod 网络接口
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ node01 路由表    │
│ 172.16.140.81/32│
│ via tunl0       │ ← 路由指向隧道接口
└────────┬────────┘
         │
         ▼
Step 2: IPIP 封装（tunl0 接口）
┌─────────────────────────────────┐
│ 外层 IP 头                        │
│ Src: 192.168.48.101 (node01)    │
│ Dst: 192.168.48.102 (node02)    │
│ Proto: 4 (IPIP)                 │
├─────────────────────────────────┤
│ 内层原始 ICMP 包                   │
│ Src: 172.16.196.180 (Pod A)     │
│ Dst: 172.16.140.81 (Pod B)      │
└─────────────────────────────────┘
         │
         ▼
Step 3: 物理网络传输（ens33 接口）
node01 ens33 ──────→ 交换机 ──────→ node02 ens33
(192.168.48.101)                  (192.168.48.102)
         │
         ▼
Step 4: IPIP 解封装（node02 tunl0）
┌─────────────────┐
│ tunl0 接口       │ ← 收到 IPIP 包
│ 解封装          │
│ 移除外层 IP 头     │
└────────┬────────┘
         │ 原始 ICMP 包
         ▼
┌─────────────────┐
│ node02 路由表    │
│ 172.16.140.81/32│
│ via cali*       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ cali* veth      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Pod B           │
│ 172.16.140.81   │
│ node02          │
└─────────────────┘

Step 5-7: 响应包按相反路径返回
```

### 各接口抓包对比

| 节点 | 接口 | 方向 | IP 源 | IP 目的 | 协议 | 说明 |
|------|------|------|-------|---------|------|------|
| node01 | tunl0 | 入 | 172.16.196.180 | 172.16.140.81 | ICMP | 封装前的原始包 |
| node01 | ens33 | 出 | 192.168.48.101 | 192.168.48.102 | IPIP(4) | IPIP 封装包 |
| node02 | ens33 | 入 | 192.168.48.101 | 192.168.48.102 | IPIP(4) | 收到封装包 |
| node02 | tunl0 | 出 | 172.16.196.180 | 172.16.140.81 | ICMP | 解封装后的包 |
| node02 | tunl0 | 入 | 172.16.140.81 | 172.16.196.180 | ICMP | 响应包（解封装后） |
| node02 | ens33 | 出 | 192.168.48.102 | 192.168.48.101 | IPIP(4) | 响应包（封装） |
| node01 | ens33 | 入 | 192.168.48.102 | 192.168.48.101 | IPIP(4) | 收到响应包 |
| node01 | tunl0 | 出 | 172.16.140.81 | 172.16.196.180 | ICMP | 响应包（解封装后） |

---

## 验证命令

### 1. 查看 Pod 分布
```bash
kubectl get pod -l app=network-tools-2 -o wide
```

### 2. 查看节点路由表
```bash
# 在 node01 上执行
ip route | grep 172.16.140.81
# 输出示例：
# 172.16.140.81 dev tunl0 proto 17 scope link src 172.16.196.64
```

### 3. 查看隧道接口
```bash
ip -d link show tunl0
# 输出示例：
# 3: tunl0@NONE: <BROADCAST,NOARP,UP> mtu 1480
#     tunnel ipip  remote  peer  ttl inherit
#     link/ether 00:00:00:00:00:00 brd 00:00:00:00:00:00
```

### 4. 查看 Calico 路由
```bash
calicoctl get ipipconfig -o yaml
# 或
kubectl get felixconfigurations.crd.projectcalico.org default -o yaml
```

### 5. 实时抓包分析
```bash
# 实时捕获并显示 IPIP 包
tshark -i ens33 -f "proto 4" -V | grep -A 20 "IP Encapsulation"
```

---

## 关键知识点

### 1. 为什么使用 IPIP 封装？
- **跨子网通信**: Pod 网络（172.16.0.0/16）与物理网络（192.168.48.0/24）隔离
- **保持 Pod IP**: 数据包在内层保持原始 Pod IP，便于网络策略实施
- **透明传输**: 上层应用无需关心底层网络拓扑

### 2. IPIP vs VXLAN
| 特性 | IPIP | VXLAN |
|------|------|-------|
| 封装开销 | 20 字节 | 50 字节 |
| 性能 | 更高 | 略低 |
| 三层路由 | 支持 | 需要 VTEP |
| 调试难度 | 较简单 | 较复杂 |

### 3. MTU 考虑
```bash
# 物理接口 MTU
ip link show ens33
# ens33: mtu 1500

# 隧道接口 MTU（减少 20 字节用于 IPIP 头）
ip link show tunl0
# tunl0: mtu 1480

# Pod 接口 MTU
ip netns exec <pod-ns> ip link show eth0
# eth0: mtu 1480
```

### 4. 性能优化
- **同节点通信**: 不经过 IPIP 封装，直接通过 cali* veth 转发
- **IPIP 自动关闭**: Calico 可以配置在直连网络中自动关闭 IPIP 封装
- **BGP 路由**: 使用 BGP 通告 Pod 路由，减少 IPIP 使用

---

## 故障排查

### 常见问题 1: 跨节点 Pod 无法通信
```bash
# 检查 tunl0 接口
ip link show tunl0

# 检查路由表
ip route | grep 172.16

# 检查 IPIP 模块
lsmod | grep ipip
# 应该看到：ipip 16384 0

# 加载 IPIP 模块（如果未加载）
modprobe ipip
```

### 常见问题 2: 抓不到 IPIP 包
```bash
# 确认过滤器正确
tshark -i ens33 -f "proto 4" -c 10

# 确认 tunl0 接口状态
ip -d link show tunl0

# 检查 Calico 配置
kubectl get felixconfigurations default -o yaml | grep -i ipip
```

### 常见问题 3: MTU 问题导致大包丢失
```bash
# 测试不同大小的包
ping -M do -s 1472 172.16.140.81  # 应该成功
ping -M do -s 1473 172.16.140.81  # 可能失败

# 解决：调整 MTU
ip link set dev tunl0 mtu 1480
```

---

## 总结

Calico IPIP 模式通过 IP-in-IP 隧道技术实现了跨节点 Pod 通信：

1. **封装过程**: 在源节点将原始 Pod 包封装在 IPIP 隧道中
2. **物理传输**: 通过物理网络在节点间传输封装包
3. **解封装**: 在目的节点移除 IPIP 外层头，露出原始包
4. **透明性**: 对应用层完全透明，保持 Pod IP 不变

通过 tshark 抓包可以清晰观察到：
- **tunl0 接口**: 原始 Pod 包（ICMP/TCP/UDP）
- **ens33 接口**: IPIP 封装包（Protocol 4）
- **封装开销**: 20 字节（外层 IP 头）

这种设计在保证性能的同时，提供了灵活的网络策略实施能力。
