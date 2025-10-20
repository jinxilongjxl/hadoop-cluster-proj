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

output "test_ssh_from_master" {
  value = <<-EOT
    # 验证 SSH 免密登录（复制以下命令到终端执行）
    gcloud compute ssh hadoop-master --zone=${var.region}-a --tunnel-through-iap --command='
      echo "Testing SSH to hadoop-worker-1..."; 
      ssh -o ConnectTimeout=10 -o BatchMode=yes hadoop-worker-1 hostname && echo "✅ SUCCESS" || echo "❌ FAILED";
      echo "Testing SSH to hadoop-worker-2..."; 
      ssh -o ConnectTimeout=10 -o BatchMode=yes hadoop-worker-2 hostname && echo "✅ SUCCESS" || echo "❌ FAILED"
    '
  EOT
}

output "hdfs_report" {
  value = "gcloud compute ssh hadoop-master --zone=${var.region}-a --command='hdfs dfsadmin -report'"
}