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

  metadata = {
    ssh-keys = "hadoop:${file("~/.ssh/id_rsa.pub")}"
  }

  metadata_startup_script = data.template_file.master_script.rendered

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
  }

  metadata_startup_script = data.template_file.worker_script.rendered

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
    ports    = ["9870", "8088"]  # HDFS, YARN
  }

  source_ranges = var.allowed_source_ips
  target_tags   = ["hadoop-cluster"]
}

# ========== 启动脚本模板 ==========
data "template_file" "master_script" {
  template = file("${path.module}/scripts/install-hadoop-master.sh")
}

data "template_file" "worker_script" {
  template = file("${path.module}/scripts/install-hadoop-worker.sh")
}