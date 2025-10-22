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
export PDSH_RCMD_TYPE=ssh
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
  echo 'Generating SSH key pair...'
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q  # 无密码生成密钥
  # 检查公钥是否生成成功
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo '❌ Failed to generate SSH public key'
    exit 1  # 生成失败则脚本退出，避免后续步骤无效
  fi
  chmod 700 ~/.ssh
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ SSH key generated for localhost'
"

# 10. 启动 Hadoop（添加重试和状态检查）
echo "🚀 Step 13: Starting Hadoop services and waiting for workers to be ready..."
cat > /tmp/start-hadoop.sh << 'EOF'
#!/bin/bash
source /home/hadoop/.bashrc

# 定义 Worker 列表和服务端口（DataNode: 9866, NodeManager: 8042）
WORKERS=("hadoop-worker-1" "hadoop-worker-2")
PORTS=("9866" "8042")
MAX_RETRIES=20  # 最大重试次数（每次间隔 10 秒，共 200 秒超时）
RETRY_DELAY=10

# 1. 先格式化并启动 Hadoop 服务（这一步会触发 Worker 启动 DataNode/NodeManager）
echo "Formatting NameNode..."
hdfs namenode -format -force

echo "Starting HDFS..."
start-dfs.sh

echo "Starting YARN..."
start-yarn.sh

# 2. 启动后，等待 Worker 的服务端口就绪（确认服务真正启动）
echo "Waiting for all workers' services to be ready..."
for worker in "${WORKERS[@]}"; do
  for port in "${PORTS[@]}"; do
    retry_count=0
    echo "Checking $worker:$port..."
    while ! nc -z $worker $port; do
      if [ $retry_count -ge $MAX_RETRIES ]; then
        echo "Error: $worker:$port not ready after $((MAX_RETRIES*RETRY_DELAY)) seconds. Service may have failed to start."
        exit 1  # 超时退出，避免无限等待
      fi
      retry_count=$((retry_count+1))
      sleep $RETRY_DELAY
    done
    echo "$worker:$port is ready"
  done
done

echo "✅ All Hadoop services (Master + Workers) are fully ready at $(date)"
EOF

chmod +x /tmp/start-hadoop.sh
su - hadoop -c "/tmp/start-hadoop.sh"
echo "✅ Hadoop services started with readiness check"