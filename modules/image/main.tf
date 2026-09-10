locals {
  # Decompressed filename (post PVE-side zstd decompression) on each node's
  # `local` storage `iso` content directory. The VM disks reference it via
  # `file_id`, which the provider imports over SSH (`pvesm path` + `qm disk
  # import`) into `local-lvm`.
  #
  # Source asset (Talos v1.13.0 nocloud, decompressed by PVE):
  #   https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.13.0/nocloud-amd64.raw.zst
  # The nocloud platform reads network config + machine config from the PVE
  # cloud-init drive at boot, giving nodes a static IP from the first boot.
  file_name = var.image_file_name != "" ? var.image_file_name : "talos-nocloud-amd64.img"
}

# Downloads the Talos nocloud image into the node-local `iso` content
# directory on EVERY online node (storage `local` is node-local, and VMs are
# round-robined across nodes). PVE only supports server-side decompression for
# the `iso` content type (not `import`), hence content_type = "iso" + zst.
resource "proxmox_download_file" "talos" {
  for_each                = toset(var.proxmox_nodes)
  node_name               = each.value
  datastore_id            = var.iso_datastore_id
  content_type            = "iso"
  file_name               = local.file_name
  url                     = var.talos_image_url
  decompression_algorithm = "zst"
  checksum                = var.talos_image_checksum
  checksum_algorithm      = "sha256"
  overwrite               = false
  upload_timeout          = 3600
}
