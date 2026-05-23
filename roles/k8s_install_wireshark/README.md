# k8s_install_wireshark

所有节点安装 tshark + WireMCP，供 LLM 实时网络抓包分析。

## 作用

- 安装 `tshark`
- 安装 Node.js（NodeSource）
- git clone [WireMCP](https://github.com/0xkoda/WireMCP) 并 `npm install`

## 执行范围

`k8s_cluster`

## 开关

`k8s_enable_wireshark=true`

## 关键变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `wireshark_package` | `tshark` | apt 包名 |
| `wiremcp_node_major` | `20` | Node.js 大版本 |
| `wiremcp_install_dir` | `/opt/WireMCP` | 安装路径 |
| `wiremcp_repo` | github 地址 | WireMCP 仓库 |

## 使用方式

```bash
ansible-playbook k8s-cluster.yaml -e k8s_enable_wireshark=true
```

## Cursor MCP 配置

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

## 镜像

无容器镜像，见 [images.txt](./images.txt)
