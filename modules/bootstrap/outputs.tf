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

output "kubeconfig_host" {
  description = "Kubernetes API server URL used by the client configuration."
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
}

output "kubeconfig_ca_certificate" {
  description = "Kubernetes CA certificate (PEM) for the provider client configuration."
  value       = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  sensitive   = true
}

output "kubeconfig_client_certificate" {
  description = "Kubernetes client certificate (PEM) for the provider client configuration."
  value       = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  sensitive   = true
}

output "kubeconfig_client_key" {
  description = "Kubernetes client private key (PEM) for the provider client configuration."
  value       = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  sensitive   = true
}