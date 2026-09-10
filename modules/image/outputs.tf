output "file_volume_id" {
  description = "Volume ID of the Talos raw image (`<datastore>:iso/<file_name>`), identical across all nodes."
  value       = "${var.iso_datastore_id}:iso/${local.file_name}"
}

output "download_nodes" {
  description = "Nodes on which the Talos image was downloaded. References all resource instances to force ordering."
  value       = keys(proxmox_download_file.talos)
}

output "file_name" {
  description = "Filename (post-decompression) of the Talos image in the storage."
  value       = local.file_name
}
