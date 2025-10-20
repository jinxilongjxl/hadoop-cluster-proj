variable "project_id" {
  description = "GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "GCP 区域"
  type        = string
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