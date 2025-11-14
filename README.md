# rke2-ansible
rke2-ansible-1.29.2
# 使用说明

rke2官方文档：[Introduction | RKE2](https://docs.rke2.io/)

需要下载rke2制品包，然后使用脚本部署rke2-k8s集群
如果是amd架构或其他k8s版本，下载同理，需自行修改playbook中文件名（arm64）以及 k8s版本号

```
# 五个文件，一个rke2-k8s安装包
制品列表：
cluster.yaml
create_config.sh
create_tls.sh
playbook.yaml
up-rke2-ansible.sh
rke2-offline-arm64-k8s1.29.2.tgz
```

## 获取rke2-k8s安装包

rke2官方链接：https://github.com/rancher/rke2/releases

我们下载版本：v1.29.2+rke2r1

```
mkdir /root/rke2-offline-arm64-k8s1.29.2

cd /root/rke2-offline-arm64-k8s1.29.2

# 下载安装脚本
curl -sfL https://get.rke2.io -o install.sh

# 下载RKE2二进制文件（ARM64架构，v1.29.2+rke2r1版本）
wget https://github.com/rancher/rke2/releases/download/v1.29.2%2Brke2r1/rke2.linux-arm64.tar.gz

# 下载镜像清单
wget https://github.com/rancher/rke2/releases/download/v1.29.2%2Brke2r1/rke2-images.linux-arm64.txt

# 下载校验和文件
wget https://github.com/rancher/rke2/releases/download/v1.29.2%2Brke2r1/sha256sum-arm64.txt



# 拉取离线镜像
# 1. 确保已下载 RKE2 镜像清单（之前步骤中的 rke2-images.linux-arm64.txt）
# 2. 创建临时目录存放单个镜像tar包
cd /root/rke2-offline-arm64-k8s1.29.2
mkdir ./rke2_images && cd ./rke2_images

# 3. 遍历镜像清单，拉取ARM64镜像并保存（关键：--platform linux/arm64）
while read -r image; do
  # 去掉镜像名中的标签后缀（如 ":v1.29.2"），避免文件名特殊字符问题
  image_filename=$(echo "$image" | sed 's/:/_/g' | sed 's/\//-/'g).tar
  # 拉取ARM64架构镜像
  docker pull --platform linux/arm64 "$image"
  # 导出镜像为tar包
  docker save "$image" -o "$image_filename"
  echo "已保存 ARM64 镜像：$image -> $image_filename"
done < ../rke2-images.linux-arm64.txt  # 注意：路径需指向你的镜像清单文件


验证镜像架构（确保是 ARM64）
拉取完成后，可任选一个镜像验证架构是否正确：
# 查看镜像的架构信息（输出 "arm64" 即为正确）
docker inspect --format '{{.Architecture}}' rancher/rke2-agent:v1.29.2-rke2r1



# 拉取calico所需镜像
cd /root/rke2-offline-arm64-k8s1.29.2
mkdir ./calico_images && cd ./calico_images

docker pull --platform linux/arm64  docker.io/rancher/mirrored-calico-operator:v1.32.3
docker pull --platform linux/arm64  docker.io/rancher/mirrored-calico-pod2daemon-flexvol:v3.27.0
docker pull --platform linux/arm64  docker.io/rancher/mirrored-calico-typha:v3.27.0
docker pull --platform linux/arm64 docker.io/rancher/mirrored-calico-cni:v3.27.0
docker pull --platform linux/arm64 docker.io/rancher/mirrored-calico-node:v3.27.0
docker pull --platform linux/arm64 docker.io/rancher/mirrored-calico-kube-controllers:v3.27.0

docker save -o docker.io-rancher-mirrored-calico-operator_v1.32.3.tar docker.io/rancher/mirrored-calico-operator:v1.32.3
docker save -o docker.io-rancher-mirrored-calico-pod2daemon-flexvol_v3.27.0.tar docker.io/rancher/mirrored-calico-pod2daemon-flexvol:v3.27.0
docker save -o docker.io-rancher-mirrored-calico-typha_v3.27.0.tar docker.io/rancher/mirrored-calico-typha:v3.27.0
docker save -o docker.io-rancher-mirrored-calico-cni_v3.27.0.tar docker.io/rancher/mirrored-calico-cni:v3.27.0
docker save -o docker.io-rancher-mirrored-calico-node_v3.27.0.tar docker.io/rancher/mirrored-calico-node:v3.27.0
docker save -o docker.io-rancher-mirrored-calico-kube-controllers_v3.27.0 docker.io/rancher/mirrored-calico-kube-controllers:v3.27.0
docker save -o docker.io-rancher-mirrored-calico-kube-controllers_v3.27.0.tar docker.io/rancher/mirrored-calico-kube-controllers:v3.27.0


# 打包
# 刚刚下载的文件：
images/{rke2_images,calico_images}
install.sh
rke2.linux-arm64.tar.gz
rke2-images.linux-arm64.txt
sha256sum-arm64.txt


# 打包所有文件
cd rke2-offline-arm64-k8s1.29.2
tar czvf rke2-offline-arm64-k8s1.29.2.tgz ./*
```

## 部署步骤

### 免密

```

一台控制节点（建议master1）与其他所有主机免密
master1：
# 取消第一次连接的输入yes
sed -i '/^#   StrictHostKeyChecking/cStrictHostKeyChecking no' /etc/ssh/ssh_config 
# 创建ssh秘钥
ssh-keygen -t rsa  // 一直回车

cat id_rsa.pub // 公钥文件
结果：
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5qlIYhuUmf/ka87riVL8vxZY1McaP5fHTIAJicK86+gL6ow6LLtxyZtfUpTZQ8A23wjGDD6HPDT2qSMYJIkKarBSPCxM31dXWVLJ8SnmlechCHhlMxkykkq+uGyGEcv9u1km9URZy3S1MJ++I7w3ixO1jKjqZMwztn81XPUjXy4R3XcQIHs+czM8xexM/6T9ye+NPmixdvqI+KdFHE6gVqyEZ9R1KCkoB7neTqiEaGgj8zS2tQt2D7zRPuZ6x9PGrc4fihUsQSJJ8e93cRQC3NIp6Rhl97yj8At8wxbxGbaTBC+Nlwd7CxFsMi6FITH1rH5rn7dnLL3jSg3XtKXXpxCUXrFJEQapMqOGP3oRCwYhhu+6ucgp1b+yP7olMRJc5bb+aRapL/fMy4iw15QU4uzH9eA/1E7iTSeQTqbx6kinNEdzIW7ZT6qdd+0mSHtsxi2+Vg+ZS8eNqQAqXz3KcRvwGRvg5buboa/nWRPw+l0QZ3k8x7CJNfDNni1AdAE= root@pm-f1d60001

其他主机：
# 将master的公钥内容，写入authorized_keys文件授权
mkdir /root/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCz5qlIYhuUmf/ka87riVL8vxZY1McaP5fHTIAJicK86+gL6ow6LLtxyZtfUpTZQ8A23wjGDD6HPDT2qSMYJIkKarBSPCxM31dXWVLJ8SnmlechCHhlMxkykkq+uGyGEcv9u1km9URZy3S1MJ++I7w3ixO1jKjqZMwztn81XPUjXy4R3XcQIHs+czM8xexM/6T9ye+NPmixdvqI+KdFHE6gVqyEZ9R1KCkoB7neTqiEaGgj8zS2tQt2D7zRPuZ6x9PGrc4fihUsQSJJ8e93cRQC3NIp6Rhl97yj8At8wxbxGbaTBC+Nlwd7CxFsMi6FITH1rH5rn7dnLL3jSg3XtKXXpxCUXrFJEQapMqOGP3oRCwYhhu+6ucgp1b+yP7olMRJc5bb+aRapL/fMy4iw15QU4uzH9eA/1E7iTSeQTqbx6kinNEdzIW7ZT6qdd+0mSHtsxi2+Vg+ZS8eNqQAqXz3KcRvwGRvg5buboa/nWRPw+l0QZ3k8x7CJNfDNni1AdAE= root@pm-f1d60001" >> /root/.ssh/authorized_keys
```

### 安装ansible

```
# 添加 Ansible 官方 PPA（该 PPA 提供高版本 ansible）
apt-add-repository --yes ppa:ansible/ansible
# 更新源缓存
apt update
# 下载到当前目录-ansible支持所有架构
apt-get install -d  -o Dir::Cache::archives="./" ansible-core -y
apt-get install -d --reinstall -o Dir::Cache::archives="./" ansible -y


# 离线安装 10.237.198.46：/dpc/awei/deb/ansible/
dpkg -i ./*


vi /etc/ansible/ansible.cfg  //添加以下配置
[default]
# 同时并行操作 10 台机器（根据需求调整默认5）
forks = 10
# 取消第一次连接的yes
host_key_checking = False
# 禁用 shell/command 模块的警告
command_warnings = False
```

### 部署集群

```
tar xf install-rke2-ansible-k8s1.29.2-arm64.tgz -C /data/

cd /data/install-rke2-ansible-k8s1.29.2-arm64 && ls
# 五个文件，一个rke2-k8s安装包，在同一路径下
制品列表：
cluster.yaml
create_config.sh
create_tls.sh
playbook.yaml
up-rke2-ansible.sh
rke2-offline-arm64-k8s1.29.2.tgz


# 修改为自己的环境信息
vi cluster.yaml 

local-address: 192.168.80.21  //本机IP（master1）

master:  # master节点IP，有几个写几个
  - 192.168.80.21
  - 192.168.80.22

node:    # node节点IP，没有则不写
  - 192.168.80.24

data-dir: /data/rke2  # 全局数据目录（etcd、cintainerd、kubelet）

calico-net: eno*  # calico网卡配置，适配多个，逗号分隔

mirrors: # harbor配置
    endpoint: https://reg.test.harbor.com
    auth:
      username: admin
      password: 123456
      
      
      
      
# 执行安装脚本
# 引用了bash扩展功能，必须使用bash
bash up-cluster-ansible.sh   

等待安装成功即可！
```

## 节点扩缩容

### 增加节点

在cluster.yaml中新增节点IP，再次执行 sh install-rke2-ansible.sh

```shell
cd /data/install-rke2-ansible-k8s1.29.2-arm64
vi cluster.yaml  
在master块或node块 增加节点IP


# 执行up脚本
# 自动识别cluster信息，已部署的节点，无操作，只会新增节点
bash up-cluster-ansible.sh   # 引用了bash扩展功能，必须使用bash
```

### 删除节点

新增和删除可以一起操作，cluster.yaml 中增减IP即可

```Shell
cd /data/install-rke2-ansible-k8s1.29.2-arm64
cluster.yaml 中，将节点ip删除或注释后

# 自动识别cluster信息，已部署的节点，无操作，只执行删除/新增操作
bash install-rke2-ansible.sh  # 引用了bash扩展功能，必须使用bash
```

## etcd备份/恢复

## 备份

默认开启备份

```Shell
# 备份位置
/data/rke2/server/db/snapshots

# 默认保留五个备份文件
root@pm-4bf40003:/data/rke2/server/db/snapshots# ll
total 471824
drwx------ 2 root root     4096 Nov 12 12:00 ./
drwx------ 4 root root       47 Oct 31 17:30 ../
-rw------- 1 root root 96624672 Nov 10 12:00 etcd-snapshot-pm-4bf40003-1762747200
-rw------- 1 root root 96624672 Nov 11 00:00 etcd-snapshot-pm-4bf40003-1762790404
-rw------- 1 root root 96624672 Nov 11 12:00 etcd-snapshot-pm-4bf40003-1762833603
-rw------- 1 root root 96624672 Nov 12 00:00 etcd-snapshot-pm-4bf40003-1762876803
-rw------- 1 root root 96624672 Nov 12 12:00 etcd-snapshot-pm-4bf40003-1762920004
```

可在/etc/rancher/rke2/config.yaml 中配置

```Markdown
# DB
# 公开 etcd metrics
# 默认：false
etcd-expose-metrics: false

# 禁用 etcd 自动快照
etcd-disable-snapshots: true

# 设置 etcd 快照的前缀名称
# 默认 "etcd-snapshot"，最终效果：etcd-snapshot-<unix-timestamp>
etcd-snapshot-name: etcd-snapshot

# 创建快照的时间间隔，
# 默认每隔 12 小时创建一次， "0 */12 * * *"
# 下面示例将每隔 5 小时创建一次快照
etcd-snapshot-schedule-cron： '0 */5 * * *'

# 要保留的快照数量，默认为 5 个
etcd-snapshot-retention: 5

# etcd 快照的保存目录，默认为：${data-dir}/db/snapshots
etcd-snapshot-dir: /opt/db/snapshots

# 压缩 etcd 快照，会压缩为 zip 格式，默认为 不开启
etcd-snapshot-compress: false

# 启用 S3 备份
etcd-s3: true
# S3 endpoint url (default: "s3.amazonaws.com")
etcd-s3-endpoint: minio.local:9000
# S3自定义CA证书连接到S3 endpoint
etcd-s3-endpoint-ca: /etc/pki/ca-trust/source/anchors/my-ca.pem
# 禁用S3 SSL证书验证
etcd-s3-skip-ssl-verify: true
# S3 access key [$AWS_ACCESS_KEY_ID]
etcd-s3-access-key: myuser
# S3 secret key [$AWS_SECRET_ACCESS_KEY]
etcd-s3-secret-key: mykey
# S3 bucket name
etcd-s3-bucket: rke2-backup
# S3 region / bucket location (optional) (default: "us-east-1")
# 如果是 minio，可不设置
etcd-s3-region: us-east-1
# S3 folder
etcd-s3-folder: rke2-folder
# 禁用 S3 https，如果你的 S3 server 是 http 的，需通过此参数来设置使用 http 访问
etcd-s3-insecure: true
# S3 timeout (default: 5m0s)，当上传的文件过大，或者网络比较慢时，需要调大此参数
etcd-s3-timeout: 5m0s

## 示例1 - 将 etcd 快照上传到 http 的 minio
## cat /etc/rancher/rke2/config.yaml
## etcd-s3: true
## etcd-s3-endpoint: 192.168.205.83:9000
## etcd-s3-access-key: myuser
## etcd-s3-secret-key: mykey
## etcd-s3-bucket: rke2-backup
## etcd-s3-folder: rke2-folder
## etcd-s3-insecure: true
## etcd-s3-timeout: 10m0s

## 示例 2 - 将快照上传到 aws S3
## etcd-s3: true
## etcd-s3-access-key: myuser
## etcd-s3-secret-key: mykey/h
## etcd-s3-region: ca-central-1
## etcd-s3-bucket: hailong-test
## etcd-s3-folder: rke2-folder
## etcd-s3-timeout: 10m0s
```

## 恢复到原主机

参考 https://docs.rke2.io/datastore/backup_restore

在此示例中，有 3 个服务器 、 和 。快照位于 上。`S1S2S3S1`

1. 在所有服务器上停止 RKE2：

```Bash
systemctl stop rke2-server
```

1. 在 S1 上，使用该选项运行，并指示要还原的快照路径。 如果快照存储在 S3 上，请提供 S3 配置标志（、 等），并仅提供快照的文件名作为还原路径。`rke2 server--cluster-reset--cluster-reset-restore-path--etcd-s3--etcd-s3-bucket`
2. **注意**
3. 使用该标志而不指定要恢复的快照只是将 etcd 集群重置为单个成员，而不恢复快照。`--cluster-reset`

```Bash
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=<PATH-TO-SNAPSHOT>
```

1. **结果：**RKE2 恢复快照并重置集群成员身份，然后打印一条消息，指示它已准备好重新启动： `Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.` `Backup and delete ${datadir}/server/db on each peer etcd server and rejoin the nodes.`
2. 在 S1 上，再次启动 RKE2：

```Bash
systemctl start rke2-server
```

1. 在 S2 和 S3 上，删除数据目录：`/var/lib/rancher/rke2/server/db/`

```Bash
rm -rf /var/lib/rancher/rke2/server/db/
```

1. 在 S2 和 S3 上，再次启动 RKE2 以加入恢复的集群：

```Bash
systemctl start rke2-server
```

如果在 RKE2 配置文件中定义了 etcd-s3 备份配置，则 RKE2 还原将尝试从配置的 S3 存储桶中提取快照文件。在这种情况下，只应在参数中传递快照文件名。要从存在 etcd-s3 备份配置的本地快照文件还原，请添加参数并在参数中传递到本地快照文件的完整路径。`--cluster-reset-restore-path--etcd-s3=false--cluster-reset-restore-path`

作为一种安全机制，当 RKE2 重置集群时，它会创建一个空文件，以防止用户意外连续运行多个集群重置。当 RKE2 正常启动时，该文件将被删除。`/var/lib/rancher/rke2/server/db/reset-flag`

## 恢复到新主机

参考 https://docs.rke2.io/datastore/backup_restore

可以将 etcd 快照恢复到与之前不同的主机。这样做时，必须传递最初在拍摄快照时使用的[服务器令牌](https://docs.rke2.io/security/token#server)，因为它用于解密快照中的引导数据。该过程与上述相同，但通过以下方式更改第 2 步：

1. 在拍摄快照的节点中，保存以下值： 步骤 3 中使用`<BACKED-UP-TOKEN-VALUE>`。

```Shell
cat $data-root/server/token
默认：/var/lib/rancher/rke2/server/token 
```

1. 将快照复制到新节点。节点中的路径位于步骤 3 中`<PATH-TO-SNAPSHOT>`

```Shell
etcd 快照路径：
$data-root/server/db/snapshots/
```

1. 使用以下命令从第一个服务器节点上的快照启动还原：

```Bash
rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=<PATH-TO-SNAPSHOT>
  --token=<BACKED-UP-TOKEN-VALUE>
```

令牌值也可以在 RKE2 配置文件中设置。

## 其他内容参考文档

```
rke2 中文文档
https://docs.rancher.cn/docs/rke2/_index/

rke2 rancher 社区相关文档（常见问题记录）
https://forums.rancher.cn/tag/rke2
```

