#!/bin/bash
exec > /var/log/hadoop-worker-install.log 2>&1

echo "=============================="
echo "🚀 Starting Hadoop Worker Installation"
echo "=============================="

# 1. 安装 Java
echo "🔧 Step 1: Installing OpenJDK 11..."
apt update -y
apt install -y openjdk-11-jdk
echo "✅ Java installed"

# 2. 创建用户
echo "👤 Step 2: Creating hadoop user..."
id hadoop &>/dev/null || useradd -m -s /bin/bash hadoop
echo "✅ Hadoop user created"

# 3. 安装 Hadoop
echo "📦 Step 3: Installing Hadoop..."
HADOOP_HOME="/home/hadoop/hadoop"
if [ ! -d "$HADOOP_HOME" ]; then
  su - hadoop -c "
    cd /home/hadoop
    wget -q https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
    tar -xzf hadoop-3.3.6.tar.gz
    mv hadoop-3.3.6 hadoop
  "
fi
echo "✅ Hadoop installed"

# 4. 配置环境变量
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/hadoop/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF

# 5. 配置 hadoop-env.sh
echo "⚙️ Step 5: Configuring hadoop-env.sh..."
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_DATANODE_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF

# 6. 创建 DataNode 目录
echo "📁 Step 6: Creating DataNode directories..."
mkdir -p $HADOOP_HOME/data/datanode
chown -R hadoop:hadoop $HADOOP_HOME/data
echo "✅ DataNode directories created"

# 7. 配置核心文件（指向主节点）
echo "⚙️ Step 7: Configuring Hadoop core files..."
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

# 复用主节点的 yarn-site.xml 和 mapred-site.xml
# （实际会由 Master 启动时同步，这里简化）
echo "⚙️ Step 9: Configuring yarn-site.xml..."
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

echo "⚙️ Step 10: Configuring mapred-site.xml..."
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

# 8. 确保 .ssh 目录存在（Master 会自动添加公钥）
echo "🔑 Step 8: Preparing SSH directory..."
su - hadoop -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  # 不添加任何公钥！Master 会通过 ssh-copy-id 自动添加
"
echo "✅ SSH directory prepared"

echo "=============================="
echo "🎉 Hadoop Worker installation completed!"
echo "=============================="