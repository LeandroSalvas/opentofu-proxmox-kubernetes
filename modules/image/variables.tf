variable "proxmox_nodes" {
  description = "All online Proxmox nodes that need a local copy of the Talos image (node-local `local` storage)."
  type        = set(string)
}

variable "iso_datastore_id" {
  description = "Proxmox storage/datastore with `iso` content where the Talos image is downloaded/decompressed."
  type        = string
}

variable "talos_image_url" {
  description = "URL of the Talos metal image (zstd-compressed raw asset) to download and decompress on each node."
  type        = string
}

variable "talos_image_checksum" {
  description = "Expected sha256 checksum of the Talos image for verification. Empty = not verified."
  type        = string
  default     = ""
}

variable "image_file_name" {
  description = "Filename (post-decompression) of the Talos image in the storage `iso` content directory."
  type        = string
  default     = "talos-amd64.img"
}
