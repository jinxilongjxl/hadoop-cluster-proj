# ========== 读取本地 SSH 公钥（用于你登录 Master）==========
data "local_file" "local_ssh_public_key" {
  filename = var.local_ssh_public_key_path
}

# ========== 自定义 VPC ==========
resource "google_compute_network" "hadoop_vpc" {
  name                    = "hadoop-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "hadoop_subnet" {
  name          = "hadoop-subnet"
  region        = var.region
  network       = google_compute_network.hadoop_vpc.id
  ip_cidr_range = "10.0.1.0/24"
}

# ========== 主节点（NameNode + ResourceManager）==========
resource "google_compute_instance" "master" {
  name         = "hadoop-master"
  machine_type = "e2-standard-2"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network    = google_compute_network.hadoop_vpc.id
    subnetwork = google_compute_subnetwork.hadoop_subnet.id
    access_config {}
  }

  # 注入你本地的公钥（用于你登录 Master）
  metadata = {
    ssh-keys = "hadoop:${data.local_file.local_ssh_public_key.content}"
  }

  metadata_startup_script = file("${path.module}/scripts/install-hadoop-master.sh")

  tags = ["hadoop-cluster"]
}

# ========== 工作节点（DataNode + NodeManager）==========
resource "google_compute_instance" "worker" {
  count        = var.worker_count
  name         = "hadoop-worker-${count.index + 1}"
  machine_type = "e2-standard-2"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 100
    }
  }

  network_interface {
    network    = google_compute_network.hadoop_vpc.id
    subnetwork = google_compute_subnetwork.hadoop_subnet.id
    access_config {}
  }

  metadata_startup_script = file("${path.module}/scripts/install-hadoop-worker.sh")

  tags = ["hadoop-cluster"]
}

# ========== 防火墙规则 ==========
resource "google_compute_firewall" "allow_internal" {
  name    = "hadoop-allow-internal"
  network = google_compute_network.hadoop_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_tags = ["hadoop-cluster"]
  target_tags = ["hadoop-cluster"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "hadoop-allow-ssh"
  network = google_compute_network.hadoop_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hadoop-cluster"]
}

resource "google_compute_firewall" "allow_web_ui" {
  name    = "hadoop-allow-web-ui"
  network = google_compute_network.hadoop_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["9870", "8088"]
  }

  source_ranges = var.allowed_source_ips
  target_tags   = ["hadoop-cluster"]
}

# 4. 新增：允许集群内部节点间ping（ICMP协议）
resource "google_compute_firewall" "allow_internal_icmp" {
  name    = "hadoop-allow-internal-icmp"
  network = google_compute_network.hadoop_vpc.id

  allow {
    protocol = "icmp"
  }

  source_tags = ["hadoop-cluster"]
  target_tags = ["hadoop-cluster"]
  description = "Allow ICMP (ping) between Hadoop cluster nodes"
}

# 5. 可选：允许外部指定IP ping（调试用）
resource "google_compute_firewall" "allow_external_icmp" {
  name    = "hadoop-allow-external-icmp"
  network = google_compute_network.hadoop_vpc.id

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]  # 替换为实际IP（如：114.114.114.114/32）
  target_tags   = ["hadoop-cluster"]
  description = "Allow ICMP (ping) from external IP to Hadoop cluster (debug)"
}

# ========== 自动化分发 SSH 公钥到所有 Worker ==========
resource "null_resource" "distribute_ssh_key" {
  depends_on = [
    google_compute_instance.master,
    google_compute_instance.worker
  ]

  provisioner "local-exec" {
    command = <<EOT
      # 1. 从Master拉取公钥
      gcloud compute scp hadoop@${google_compute_instance.master.name}:~/.ssh/id_rsa.pub ./master_rsa.pub

      # 2. 分发到所有Worker
      %{ for i, worker in google_compute_instance.worker ~}
        gcloud compute ssh hadoop@${worker.name} --zone=${worker.zone} --command "cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys" < ./master_rsa.pub
      %{ endfor ~}

      # 3. 清理临时文件
      rm ./master_rsa.pub
    EOT
  }
}