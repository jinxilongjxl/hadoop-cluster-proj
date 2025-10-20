#!/bin/bash
exec > /var/log/hadoop-master-install.log 2>&1

echo "=============================="
echo "🚀 Starting Hadoop Master Installation"
echo "=============================="

# 1. 安装 Java 和工具
echo "🔧 Step 1: Installing OpenJDK 11 and at..."
apt update -y
apt install -y openjdk-11-jdk at
systemctl start atd
echo "✅ Java installed: $(java -version 2>&1 | head -1)"

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

# 4. 配置环境变量
echo "⚙️ Step 4: Configuring environment variables..."
cat > /home/hadoop/.bashrc << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/home/hadoop/hadoop
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF
echo "✅ .bashrc configured"

# 5. 配置 hadoop-env.sh
echo "⚙️ Step 5: Configuring hadoop-env.sh..."
cat >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh << 'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HDFS_NAMENODE_USER=hadoop
export HDFS_DATANODE_USER=hadoop
export YARN_RESOURCEMANAGER_USER=hadoop
export YARN_NODEMANAGER_USER=hadoop
EOF
echo "✅ hadoop-env.sh updated"

# 6. 创建 NameNode 目录
echo "📁 Step 6: Creating NameNode directories..."
mkdir -p $HADOOP_HOME/data/namenode
chown -R hadoop:hadoop $HADOOP_HOME/data
echo "✅ NameNode directories created"

# 7. 配置 Hadoop 核心文件
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

# 8. 配置 workers 文件
echo "⚙️ Step 11: Configuring workers file..."
cat > $HADOOP_HOME/etc/hadoop/workers <<EOF
hadoop-worker-1
hadoop-worker-2
EOF
echo "✅ Workers file created"

# 9. 配置 SSH 免密登录（主节点到所有节点）
echo "🔑 Step 12: Setting up SSH passwordless login..."
su - hadoop -c "
  echo 'Generating SSH key...'
  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa -q
  cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo '✅ SSH key generated for localhost'
  
  # 等待工作节点启动后，自动接受主节点公钥
  # 工作节点脚本会处理 authorized_keys
"
echo "✅ SSH setup completed for master"

# 10. 启动 Hadoop
echo "🚀 Step 13: Scheduling Hadoop startup..."
cat > /tmp/start-hadoop-master.sh << 'EOF'
#!/bin/bash
source /home/hadoop/.bashrc
echo "Formatting NameNode..."
hdfs namenode -format -force
echo "Starting HDFS..."
start-dfs.sh
echo "Starting YARN..."
start-yarn.sh
echo "✅ Hadoop services started at $(date)"
EOF

chmod +x /tmp/start-hadoop-master.sh
su - hadoop -c "at -f /tmp/start-hadoop-master.sh now"
echo "✅ Hadoop startup scheduled"

echo "=============================="
echo "🎉 Hadoop Master installation completed!"
echo "=============================="