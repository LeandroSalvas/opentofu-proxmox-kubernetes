output "kubeconfig_raw" {
  description = "Raw kubeconfig for the new Kubernetes cluster (sensitive)."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talos_config" {
  description = "talosclient configuration (talosconfig) for talosctl (sensitive)."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs (sorted by node name)."
  value       = local.controlplane_ips
}

output "worker_ips" {
  description = "Worker node IPs (sorted by node name)."
  value       = local.worker_ips
}

output "bootstrap_node_ip" {
  description = "IP of the node used for the initial etcd bootstrap."
  value       = local.bootstrap_node_ip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint the cluster was configured with."
  value       = var.cluster_endpoint
}