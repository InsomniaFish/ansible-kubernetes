#!/bin/bash

# Calico IPIP 模式 Pod 跨节点通信抓包演示脚本
# 使用 network-tools-2-f5w5n 和 network-tools-2-zp6zj 两个 Pod

set -e

echo "=============================================="
echo "  Calico IPIP 模式 Pod 跨节点通信抓包演示"
echo "=============================================="
echo ""

# 检查 Pod 状态
echo "📊 检查 Pod 状态..."
kubectl get pod -l app=network-tools-2 -o wide
echo ""

# 获取 Pod IP
POD1_IP=$(kubectl get pod network-tools-2-f5w5n -o jsonpath='{.status.podIP}')
POD2_IP=$(kubectl get pod network-tools-2-zp6zj -o jsonpath='{.status.podIP}')
POD1_NODE=$(kubectl get pod network-tools-2-f5w5n -o jsonpath='{.spec.nodeName}')
POD2_NODE=$(kubectl get pod network-tools-2-zp6zj -o jsonpath='{.spec.nodeName}')

echo "📍 Pod 信息:"
echo "  network-tools-2-f5w5n: $POD1_IP (节点：$POD1_NODE)"
echo "  network-tools-2-zp6zj: $POD2_IP (节点：$POD2_NODE)"
echo ""

if [ "$POD1_NODE" == "$POD2_NODE" ]; then
    echo "⚠️  警告：两个 Pod 在同一节点上，无法演示跨节点 IPIP 封装！"
    echo "   建议删除一个 Pod 让 DaemonSet 重新调度到不同节点："
    echo "   kubectl delete pod network-tools-2-f5w5n"
    echo ""
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "🚀 开始执行 Ansible Playbook..."
echo ""

cd /root/ansible-kubernetes

ansible-playbook -i hosts.ini capture-calico-ipip.yml

echo ""
echo "=============================================="
echo "  抓包完成！"
echo "=============================================="
echo ""
echo "📁 抓包文件位置:"
echo "  master01: /tmp/tshark_master01_ipip.txt"
echo "  node01:   /tmp/tshark_node01_ipip.txt"
echo "  node02:   /tmp/tshark_node02_ipip.txt"
echo ""
echo "💡 查看抓包结果:"
echo "  1. 查看 ens33 接口（IPIP 外层包）"
echo "  2. 查看 tunl0 接口（解封装后的原始包）"
echo "  3. 对比不同节点的抓包数据"
echo ""
