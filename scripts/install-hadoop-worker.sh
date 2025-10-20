#!/bin/bash
exec > /var/log/hadoop-worker-install.log 2>&1

echo "Installing Hadoop Worker (DataNode + NodeManager)..."

# 1. 安装 Java
apt update -y
apt install -y openjdk-11-jdk

# 2. 创建用户
id hadoop &>/dev/null || useradd -m -s /bin/bash hadoop

# 3. 安装 Hadoop（同主节点）
HADOOP_HOME="/home/hadoop/hadoop"
if [ ! -d "$HADOOP_HOME" ]; then
  su - hadoop -c "
    cd /home/hadoop
    wget -q https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
    tar -xzf hadoop-3.3.6.tar.gz
    mv hadoop-3.3.6 hadoop
  "
fi

# 4. 配置环境变量
cat > /home/hadoop/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF

# 5. 配置 hadoop-env.sh（同主节点）
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_DATANODE_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF

# 6. 创建 DataNode 目录
mkdir -p $HADOOP_HOME/data/datanode
chown -R hadoop:hadoop $HADOOP_HOME/data

# 7. 从主节点同步配置（简化：直接写死）
cat > $HADOOP_HOME/etc/hadoop/core-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://hadoop-master:9000</value>
  </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/hdfs-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>2</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/home/hadoop/hadoop/data/datanode</value>
  </property>
</configuration>
EOF

# 其他配置同主节点（yarn-site.xml, mapred-site.xml）
cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>hadoop-master</value>
  </property>
  <property>
    <name>yarn.resourcemanager.webapp.address</name>
    <value>0.0.0.0:8088</value>
  </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/mapred-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>yarn.app.mapreduce.am.env</name>
    <value>HADOOP_MAPRED_HOME=/home/hadoop/hadoop</value>
  </property>
  <property>
    <name>mapreduce.map.env</name>
    <value>HADOOP_MAPRED_HOME=/home/hadoop/hadoop</value>
  </property>
  <property>
    <name>mapreduce.reduce.env</name>
    <value>HADOOP_MAPRED_HOME=/home/hadoop/hadoop</value>
  </property>
</configuration>
EOF


# 8. 允许主节点 SSH 免密登录（关键！）
# 工作节点需接受主节点的公钥
# 实际中可通过 metadata 传递，这里简化：手动添加
# 在生产环境建议用 Terraform provisioner 或 Ansible

echo "Worker setup completed."