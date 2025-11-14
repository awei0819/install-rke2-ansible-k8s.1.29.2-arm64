#!/bin/bash
Data_Dir=$(cat cluster.yaml | grep data-dir | awk -F' ' '{print $NF}')
Master_List=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
Node_List=$(sed -n '/^node:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
All_Nodes="$Master_list $Node_list"
Local_Address="$(cat cluster.yaml | grep local-address | awk -F' ' '{print $NF}')"
Harbor_EP=$(cat cluster.yaml | grep endpoint | awk -F' ' '{print $NF}')
Harbor_NM=$(cat cluster.yaml | grep endpoint | awk -F' ' '{print $NF}' | awk -F'/' '{print $NF}')
Harbor_User=$(cat cluster.yaml | egrep "^      username" | awk -F' ' '{print $NF}')
Harbor_PWD=$(cat cluster.yaml | egrep "^      password" | awk -F' ' '{print $NF}')

Error_Exit() {
	{ echo "== Error! exit 1 =="; exit 1; }
}


Create_Config() {
cat > /root/rke2-artifacts/.rke2-server-config.yaml << EOF
write-kubeconfig-mode: "0600"
tls-san:
EOF


for i in $(echo $Master_List); do
	echo "  - $i" >> /root/rke2-artifacts/.rke2-server-config.yaml
done
for i in $(echo $Master_List); do
	echo "  - $(ssh $i hostname)" >> /root/rke2-artifacts/.rke2-server-config.yaml
done


cat >> /root/rke2-artifacts/.rke2-server-config.yaml << EOF

cni: calico

disable: rke2-ingress-nginx  # 可选，指定不安装ingress

# 全局数据目录
data-dir: $Data_Dir

# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"

# etcd-metrics监听地址
etcd-arg:
  - "--listen-metrics-urls=http://0.0.0.0:2381"

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"

# kube-controller-manager 监听地址
kube-controller-manager-arg:
  - "--bind-address=0.0.0.0"

# kube-scheduler 监听地址
kube-scheduler-arg:
  - "--bind-address=0.0.0.0"
EOF
cat > /root/rke2-artifacts/.rke2-agent-config.yaml << EOF

cni: calico

disable: rke2-ingress-nginx  # 可选，指定不安装ingress

# 全局数据目录
data-dir: $Data_Dir

# 仓库配置
private-registry: "/etc/rancher/rke2/registries.yaml"

# kube-proxy-metrics监听地址
kube-proxy-arg:
  - "--metrics-bind-address=0.0.0.0:10249"
EOF

cat > /root/rke2-artifacts/.registries.yaml << EOF
mirrors:
  "$Harbor_NM":
    endpoint:
      - "$Harbor_EP"

configs:
  "reg.jthh.icloud.sinopec.com":
    auth:
      username: "$Harbor_User"
      password: "$Harbor_PWD"
    tls:
      insecure_skip_verify: true
EOF
}

echo "==== create config.yaml......"
Create_Config
echo "== server"
for node in $(echo $Master_List); do
scp /root/rke2-artifacts/.rke2-server-config.yaml $node:/etc/rancher/rke2/config.yaml &> /dev/null && \
scp /root/rke2-artifacts/.registries.yaml $node:/etc/rancher/rke2/registries.yaml &> /dev/null && \
echo "== $node OK" || Error_Exit
done
echo "== node"
for node in $(echo $Node_List); do
scp /root/rke2-artifacts/.rke2-agent-config.yaml $node:/etc/rancher/rke2/config.yaml &> /dev/null && \
scp /root/rke2-artifacts/.registries.yaml $node:/etc/rancher/rke2/registries.yaml &> /dev/null && \
echo "== $node OK" || Error_Exit
done
echo ""


echo "==== check config.yaml......"
ansible rke2-masters -i ansible-hosts -m shell -a 'sed -i "/^cni: calico/inode-name: $(hostname)" /etc/rancher/rke2/config.yaml' &> /dev/null && \
echo "== OK" || Error_Exit
for node in $Master_List; do
ssh $node cat /etc/rancher/rke2/config.yaml | grep node-name:
done