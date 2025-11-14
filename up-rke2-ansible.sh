#!/bin/bash
# 获取 cluster.yaml 中定义的节点信息
Master_List=$(sed -n '/^master:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
Worker_List=$(sed -n '/^node:/{n; :a; /^  - /p; n; /^  - /ba}' cluster.yaml | awk -F' ' '{print $NF}')
All_Nodes="$Master_List $Worker_List"
Calico_Net=$(cat cluster.yaml | grep calico-net | awk -F' ' '{print $NF}')


# 先检查 kubectl 是否安装,决定是否使用kubelet获取当前集群节点信息
if command -v kubectl &> /dev/null; then
    Get_Masters="$(kubectl get node -o wide 2> /dev/null | egrep "master|control-plane" | awk '{print $6}')"
	Get_Workers="$(kubectl get node -o wide 2> /dev/null | egrep -v "master|control-plane|STATUS" | awk '{print $6}')"
else
    Get_Masters=""
    Get_Workers=""
fi

# 当前集群节点信息变量，所有节点列表，新增的节点，需删除的节点
Get_All_Nodes="$Get_Masters $Get_Workers"
New_Masters=$(echo "$Master_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Masters" | tr ' ' '\n') 2> /dev/null)
New_Workers=$(echo "$Worker_List" | tr ' ' '\n' | grep -Fxvf <(echo "$Get_Workers" | tr ' ' '\n') 2> /dev/null)
New_Nodes="$New_Masters $New_Workers"
Del_Masters=$(echo "$Get_Masters" | tr ' ' '\n' | grep -Fxvf <(echo "$Master_List" | tr ' ' '\n') 2> /dev/null)
Del_Workers=$(echo "$Get_Workers" | tr ' ' '\n' | grep -Fxvf <(echo "$Worker_List" | tr ' ' '\n') 2> /dev/null)
Del_Nodes="$Del_Masters $Del_Workers"


# 按照cluster.yaml 中的节点信息，初始化ansible-hosts文件
init_hosts(){
echo "==== init ansible-hosts"
echo "[rke2]" > ansible-hosts
for node in $(echo $All_Nodes); do
echo "$node" >> ansible-hosts
done
echo "[rke2-masters]" >> ansible-hosts
for node in $Master_List; do
echo "$node" >> ansible-hosts
done
echo "[rke2-workers]" >> ansible-hosts
for node in $Worker_List; do
echo "$node" >> ansible-hosts
done
cat ansible-hosts
echo ""
}

# 初始化更新集群所使用的ansible-hosts-up文件
update_hosts(){
echo "==== init ansible-hosts-up"
echo "[rke2]" > ansible-hosts-up
for node in $(echo $New_Nodes); do
echo "$node" >> ansible-hosts-up
done
echo "[rke2-masters]" >> ansible-hosts-up
for node in $New_Masters; do
echo "$node" >> ansible-hosts-up
done
echo "[rke2-workers]" >> ansible-hosts-up
for node in $New_Workers; do
echo "$node" >> ansible-hosts-up
done
cat ansible-hosts-up
echo ""
}

# 判断Masters节点列表是否为空，决定是否初始化部署集群
if [ -z "$Get_Masters" ]; then
	# 提示信息
	if echo "$Master_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
	    echo "[rke2-masters]"
		for i in $Master_List; do
		    echo $i
		done
	fi
	echo ""
	if echo "$Worker_List" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
	    echo "[rke2-workers]"
		for i in $Worker_List; do
		    echo $i
		done
	fi
	echo ""
	echo "当前操作： 初始化部署k8s集群"
# 读取用户输入，根据输入操作
	while true; do
		read -p "请确认以上节点信息，输入后继续(y/n): " choice
		case "$choice" in
			y|Y)
				break
				;;
			n|N)
				exit 0
				;;
			*)
				echo "输入无效，请重新输入(y/n)。"
				;;
		esac
	done

	# 初始化部署操作
	init_hosts
	# ansible 部署集群
	ansible-playbook -i ansible-hosts playbook.yaml || exit 1
	echo "==== kube-proxy 添加 label k8s-app: kube-proxy ......"
	for i in `kubectl get pod -n kube-system --show-labels | grep kube-proxy | grep -v k8s-app | awk '{print $1}'`; do kubectl label pod -n kube-system $i k8s-app=kube-proxy; done  &&  echo "== ok =="  && echo "" || \
	echo "== label 添加失败，请检查！=="
	
	echo "==== 修改calico配置-使用网卡-$Calico_Net"
	echo "==== 等待资源就绪 installation default -n calico-system ......"
	while true; do
	    kubectl get installation default -n calico-system &> /dev/null
		if [ $? -eq 0 ]; then
			kubectl patch installation default -n calico-system \
				--type merge \
				-p "{\"spec\":{\"calicoNetwork\":{\"nodeAddressAutodetectionV4\":{\"interface\":\"$Calico_Net\", \"firstFound\": null}}}}"
			if [ $? -eq 0 ]; then
				echo "== calico 网卡已修改： $Calico_Net =="
				echo "== 部署完成！=="
				kubectl get node
				exit 0
			else
				echo "==== calico网卡修改失败，请检查！！ ===="
				echo "== 部署完成！=="
				kubectl get node
				exit 1
			fi
		else
		    sleep 1
			continue
		fi
	done

# 判断是否有需要新增或删除的节点IP，执行扩缩容操作
elif echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
	# 提示信息
	if echo "$New_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
	    echo "[rke2-masters]"
		if echo "$Del_Masters" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
		    for i in $Del_Masters; do
			    echo "$i - 删除"
			done
		fi
		for i in $New_Masters; do
		    echo "$i - 新增"
		done
	fi
	echo ""
	if echo "$New_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}' || echo "$Del_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
	    echo "[rke2-workers]"
		if echo "$Del_Workers" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
		    for i in $Del_Workers; do
			    echo "$i - 删除"
			done
		fi
		for i in $New_Workers; do
		    echo "$i - 新增"
		done
	fi
	echo ""
	echo "当前操作： k8s节点扩缩容"
	# 读取用户输入，根据输入操作
	while true; do
		read -p "请确认以上节点信息，输入后继续(y/n): " choice
		case "$choice" in
			y|Y)
				break
				;;
			n|N)
				exit 0
				;;
			*)
				echo "输入无效，请重新输入(y/n)。"
				;;
		esac
	done

	# 删除节点
	if echo "$Del_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
		echo "====== 删除节点 ======"
		DATE=$(date +%Y%m%d%H%M%S)
		for i in $Del_Nodes; do
			Node_name=$(kubectl get node -o wide | grep $i | awk '{print $1}')
			echo "== $i 删除中......"
			echo "== kubectl delete node $Node_name ......"
			kubectl delete node $Node_name && echo "== ${Node_name}/$i - 节点已从集群中删除" || { echo "== $i - kubectl delete 执行失败，请检查！"; exit 1; }
			echo "== bash rke2-killall.sh......"
			ssh $i rke2-killall.sh &> /dev/null && echo "== $i - rke2-killall.sh 已执行" || { echo "[WARNING]: $i - rke2-killall.sh 执行失败，请检查！"; sleep 2; }
			echo "== bash rke2-uninstall.sh......"
			ssh $i rke2-uninstall.sh &> /dev/null && echo "== $i - rke2-uninstall.sh 已执行" || { echo "[WARNING]: $i - rke2-uninstall.sh 执行失败，请检查！"; sleep 2; }
			echo "== rm /data/rke2......"
#			ssh $i mv /data/rke2{,-$DATE} &> /dev/null && echo "== $i - /data/rke2-$DATE 已备份" || { echo "[WARNING]: $i - /data/rke2 删除失败，请检查！"; sleep 2; }
			ssh $i rm -rf /data/rke2 &> /dev/null && echo "== $i - /data/rke2 已删除" || { echo "[WARNING]: $i - /data/rke2 删除失败，请检查！"; sleep 2; }
			echo ""
		done
		echo "== 删除节点已完成！"
		echo ""
	fi

	# 新增节点
	if echo "$New_Nodes" | egrep -q '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
		echo "====== 新增节点 ======"
		init_hosts
		update_hosts
		ansible-playbook -i ansible-hosts-up playbook.yaml && echo "== OK ==" || exit 1
		echo "==== kube-proxy 添加 label k8s-app: kube-proxy ......"
		for i in `kubectl get pod -n kube-system --show-labels | grep kube-proxy | grep -v k8s-app | awk '{print $1}'`; do kubectl label pod -n kube-system $i k8s-app=kube-proxy; done  &&  echo "== ok =="  && echo "" || \
		echo "== label 添加失败，请检查！=="
		echo "==== 新增节点已完成！ ===="
		for i in $New_Nodes; do
			kubectl get node -o wide | grep "$i"
		done
	fi
else
    echo "当前集群已部署，未检测到需要新增/删除节点，请检查cluster.yaml 并确认您要执行的操作！"
fi

