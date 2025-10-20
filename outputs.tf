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