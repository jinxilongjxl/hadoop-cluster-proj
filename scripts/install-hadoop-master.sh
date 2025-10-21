#!/bin/bash
set -e  # 出错即退出，增强健壮性
exec > /var/log/hadoop-master-install.log 2>&1

echo "=============================="
echo "🚀 Starting Hadoop Master Installation"
echo "=============================="

# 1. 安装 Java、SSH 依赖及工具
echo "🔧 Step 1: Installing OpenJDK 11 + SSH 依赖..."
apt update -y
apt install -y openjdk-11-jdk openssh-server pdsh at
systemctl start atd
echo "✅ Java + SSH 依赖安装完成: $(java -version 2>&1 | head -1)"

# 2. 创建 hadoop 用户
echo "👤 Step 2: Creating hadoop user..."
id hadoop &>/dev/null || useradd -m -s /bin/bash hadoop
echo "✅ Hadoop user created"

# 3. 安装 Hadoop
echo "📦 Step 3: Installing Hadoop 3.3.6..."
HADOOP_HOME="/home/hadoop/hadoop"
if [ ! -d "$HADOOP_HOME" ]; then
  su - hadoop -c "
    cd /home/hadoop
    echo '📥 Downloading Hadoop...'
    wget -q https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz || exit 1
    echo '🔍 Extracting Hadoop...'
    tar -xzf hadoop-3.3.6.tar.gz || exit 1
    mv hadoop-3.3.6 hadoop
    echo '✅ Hadoop installed successfully.'
  "
else
  echo "✅ Hadoop already installed"
fi

# 4. 配置环境变量（并修复权限）
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/hadoop/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF
chown hadoop:hadoop /home/hadoop/.bashrc  # 修复所有者
echo "✅ .bashrc configured"

# 5. 配置 hadoop-env.sh（并修复权限）
echo "⚙️ Step 5: Configuring hadoop-env.sh..."
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_NAMENODE_USER=hadoop
export HDFS_DATANODE_USER=hadoop
export YARN_RESOURCEMANAGER_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/hadoop-env.sh  # 修复权限
echo "✅ hadoop-env.sh updated"

# 6. 创建 NameNode 目录（并修复权限）
echo "📁 Step 6: Creating NameNode directories..."
mkdir -p $HADOOP_HOME/data/namenode
chown -R hadoop:hadoop $HADOOP_HOME/data
echo "✅ NameNode directories created"

# 7. 配置 Hadoop 核心文件（并修复权限）
echo "⚙️ Step 7: Configuring core-site.xml..."
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

echo "⚙️ Step 8: Configuring hdfs-site.xml..."
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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/hdfs-site.xml  # 修复权限

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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/yarn-site.xml  # 修复权限

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
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/mapred-site.xml  # 修复权限
echo "✅ Hadoop 核心配置文件配置完成"

# 8. 配置 workers 文件
echo "⚙️ Step 11: Configuring workers file..."
cat > $HADOOP_HOME/etc/hadoop/workers <<EOF
hadoop-worker-1
hadoop-worker-2
EOF
chown hadoop:hadoop $HADOOP_HOME/etc/hadoop/workers  # 修复权限
echo "✅ Workers file created"

# 9. 生成 Master 自身的 SSH 密钥（用于 localhost 免密）
echo "🔑 Step 12: Generating SSH key for localhost..."
su - hadoop -c "
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q
  chmod 700 ~/.ssh
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ SSH key generated for localhost'
"

# 10. 启动 Hadoop（添加重试和状态检查）
echo "🚀 Step 13: Starting Hadoop services..."
cat > /tmp/start-hadoop.sh << 'EOF'
#!/bin/bash
source /home/hadoop/.bashrc

# 等待 Worker 节点 SSH 服务就绪
for worker in hadoop-worker-1 hadoop-worker-2; do
  echo "Waiting for $worker to be ready..."
  while ! nc -z $worker 22; do
    sleep 30
  done
  echo "$worker is ready"
done

# 格式化 NameNode（仅首次启动需执行，此处通过 -force 强制）
echo "Formatting NameNode..."
hdfs namenode -format -force

# 启动 HDFS 和 YARN
echo "Starting HDFS..."
start-dfs.sh
echo "Starting YARN..."
start-yarn.sh

echo "✅ Hadoop services started at $(date)"
EOF

chmod +x /tmp/start-hadoop.sh
su - hadoop -c "/tmp/start-hadoop.sh"  # 直接执行，而非通过 at 延迟
echo "✅ Hadoop services started"

echo "=============================="
echo "🎉 Hadoop Master installation completed!"
echo "=============================="