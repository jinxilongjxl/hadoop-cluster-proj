variable "project_id" {
  description = "GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "GCP 区域"
  type        = string

variable "worker_count" {
  description = "DataNode 数量"
  type        = number
  default     = 2
}