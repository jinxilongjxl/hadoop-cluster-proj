output "master_ip" {
  value = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
}

output "worker_ips" {
  value = [for w in google_compute_instance.worker : w.network_interface[0].network_ip]
}

output "ssh_to_master" {
  value = "ssh -i ~/.ssh/id_rsa hadoop@${google_compute_instance.master.network_interface[0].access_config[0].nat_ip}"
}

output "hdfs_ui" {
  value = "http://${google_compute_instance.master.network_interface[0].access_config[0].nat_ip}:9870"
}

output "yarn_ui" {
  value = "http://${google_compute_instance.master.network_interface[0].access_config[0].nat_ip}:8088"
}

# ========== SSH 免密登录验证命令 ==========
output "ssh_master_to_workers" {
  value = <<-EOT
    # 从主节点 SSH 到所有工作节点（应无需密码）
    ssh hadoop@hadoop-master 'ssh hadoop@hadoop-worker-1 "hostname"'
    ssh hadoop@hadoop-master 'ssh hadoop@hadoop-worker-2 "hostname"'
    
    # 或直接在主节点执行：
    # gcloud compute ssh hadoop-master --zone=${var.region}-a
    # 然后运行：
    # ssh hadoop-worker-1
    # ssh hadoop-worker-2
  EOT
}

output "hdfs_report_command" {
  value = "gcloud compute ssh hadoop-master --zone=${var.region}-a --command='hdfs dfsadmin -report'"
}

output "test_ssh_from_master" {
  value = <<-EOT
    # 验证 SSH 免密登录是否成功
    gcloud compute ssh hadoop-master --zone=${var.region}-a --tunnel-through-iap --command='
      echo "Testing SSH to hadoop-worker-1..."; 
      ssh -o ConnectTimeout=10 -o BatchMode=yes hadoop-worker-1 exit && echo "✅ SUCCESS" || echo "❌ FAILED";
      echo "Testing SSH to hadoop-worker-2..."; 
      ssh -o ConnectTimeout=10 -o BatchMode=yes hadoop-worker-2 exit && echo "✅ SUCCESS" || echo "❌ FAILED"
    '
  EOT
}