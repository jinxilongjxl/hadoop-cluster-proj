#!/bin/bash
exec > /var/log/hadoop-master-install.log 2>&1

echo "Installing Hadoop Master (NameNode + ResourceManager)..."

# 1. 安装 Java 和工具
apt update -y
apt install -y openjdk-11-jdk at
systemctl start atd

# 2. 创建用户
id hadoop &>/dev/null || useradd -m -s /bin/bash hadoop

# 3. 安装 Hadoop
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

# 5. 配置 hadoop-env.sh
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_NAMENODE_USER=hadoop
export HDFS_DATANODE_USER=hadoop
export YARN_RESOURCEMANAGER_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF

# 6. 创建数据目录
mkdir -p $HADOOP_HOME/data/namenode
chown -R hadoop:hadoop $HADOOP_HOME/data

# 7. 配置核心文件
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
    <name>dfs.namenode.name.dir</name>
    <value>/home/hadoop/hadoop/data/namenode</value>
  </property>
</configuration>
EOF

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

# 8. 配置 workers 文件（DataNode 列表）
cat > $HADOOP_HOME/etc/hadoop/workers << 'EOF'
hadoop-worker-1
hadoop-worker-2
EOF

# 9. 配置 SSH 免密（主节点到所有节点）
su - hadoop -c "
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
"

# 10. 分发公钥到工作节点（通过 metadata 传递 IP）
# 注意：实际生产中建议用 Ansible，这里简化处理
# 工作节点脚本会自动接受主节点公钥

# 11. 启动脚本
cat > /tmp/start-hadoop-master.sh << 'EOF'
#!/bin/bash
source /home/hadoop/.bashrc
hdfs namenode -format -force
start-dfs.sh
start-yarn.sh
EOF

chmod +x /tmp/start-hadoop-master.sh
su - hadoop -c "at -f /tmp/start-hadoop-master.sh now"