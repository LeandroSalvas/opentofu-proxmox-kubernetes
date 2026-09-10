output "proxmox_online_nodes" {
  description = "Proxmox nodes detected as online."
  value       = local.online_nodes_sorted
}

output "master_nodes" {
  description = "Kubernetes control plane nodes and their placement (name -> { ip, node })."
  value       = local.master_nodes
}

output "worker_nodes" {
  description = "Kubernetes worker nodes and their placement (name -> { ip, node })."
  value       = local.worker_nodes
}

output "talos_image" {
  description = "Talos raw image downloaded/decompressed into each node's local storage."
  value = {
    url          = var.talos_image_url
    file_id      = module.image.file_volume_id
    file_name    = module.image.file_name
    datastore_id = var.iso_datastore_id
    nodes        = module.image.download_nodes
  }
}

output "master_vms" {
  description = "Provisioned control plane VMs."
  value       = module.compute.master_vms
}

output "worker_vms" {
  description = "Provisioned worker VMs."
  value       = module.compute.worker_vms
}

# ---------------------------------------------------------------------------
# Phase 2 outputs
# ---------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "Kubernetes API endpoint used by the cluster."
  value       = local.cluster_endpoint
}

output "controlplane_ips" {
  description = "Control plane node IPs (talosctl/kubectl endpoints)."
  value       = module.bootstrap.controlplane_ips
}

output "worker_ips" {
  description = "Worker node IPs."
  value       = module.bootstrap.worker_ips
}

output "kubeconfig_raw" {
  description = "Kubeconfig for the new cluster (write it to a file to use kubectl)."
  value       = module.bootstrap.kubeconfig_raw
  sensitive   = true
}

output "talos_config" {
  description = "talosconfig for connecting with talosctl."
  value       = module.bootstrap.talos_config
  sensitive   = true
}
