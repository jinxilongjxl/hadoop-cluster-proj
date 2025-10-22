#!/bin/bash
set -e  # 出错即退出，增强健壮性
exec > /var/log/hadoop-worker-install.log 2>&1

echo "=============================="
echo "🚀 Starting Hadoop Worker Installation"
echo "=============================="

# 1. 安装 Java、SSH 依赖
echo "🔧 Step 1: Installing OpenJDK 11 + SSH 依赖..."
apt update -y
apt install -y openjdk-11-jdk openssh-server pdsh
echo "✅ Java + SSH 依赖安装完成"

# 2. 创建 hadoop 用户
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

# 4. 配置环境变量（并修复权限）
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/hadoop/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF
chown hadoop:hadoop /home/hadoop/.bashrc  # 修复所有者
echo "✅ 环境变量配置完成"

# 5. 配置 hadoop-env.sh（并修复权限）
echo "⚙️ Step 5: Configuring hadoop-env.sh..."
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_DATANODE_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/hadoop-env.sh  # 修复权限
echo "✅ hadoop-env.sh 配置完成"

# 6. 创建 DataNode 目录（并修复权限）
echo "📁 Step 6: Creating DataNode directories..."
mkdir -p $HADOOP_HOME/data/datanode
chown -R hadoop:hadoop $HADOOP_HOME/data
echo "✅ DataNode 目录创建完成"

# 7. 配置核心文件（并修复权限）
echo "⚙️ Step 7: Configuring Hadoop core files..."
# 配置 core-site.xml
cat > $HADOOP_HOME/etc/hadoop/core-site.xml << 'EOF'
<?xml version="1.0"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://hadoop-master:9000</value>
  </property>
</configuration>
EOF
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/core-site.xml  # 修复权限

# 配置 hdfs-site.xml
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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/hdfs-site.xml  # 修复权限

# 配置 yarn-site.xml
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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/yarn-site.xml  # 修复权限

# 配置 mapred-site.xml
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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/mapred-site.xml  # 修复权限
echo "✅ Hadoop 核心配置文件配置完成"

# 8. 准备 SSH 目录（供 Master 免密登录）
echo "🔑 Step 8: Preparing SSH directory..."
su - hadoop -c "
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  touch ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ authorized_keys file created'  
"
echo "✅ SSH 目录准备完成"

echo "=============================="
echo "🎉 Hadoop Worker 安装完成！"
echo "=============================="
echo "✅ Hadoop Worker installation completed! Services ready for remote start."