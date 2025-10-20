variable "project_id" {
  description = "GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "GCP 区域"
  type        = string
  default     = "us-central1"
}

variable "worker_count" {
  description = "DataNode 数量"
  type        = number
  default     = 2
}

variable "allowed_source_ips" {
  description = "允许访问 Web UI 的源 IP"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "local_ssh_public_key_path" {
  description = "本地 SSH 公钥路径（用于你登录 Master）"
  type        = string
  default     = "/home/g18862805171/.ssh/id_rsa.pub"  # Cloud Shell 路径
  # default     = "/Users/yourname/.ssh/id_rsa.pub"    # macOS
  # default     = "C:/Users/yourname/.ssh/id_rsa.pub"  # Windows
}