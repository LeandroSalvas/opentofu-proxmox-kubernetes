variable "online_nodes" {
  description = "Sorted list of 'online' Proxmox nodes detected dynamically."
  type        = list(string)
}

variable "talos_image_file_id" {
  description = "File ID of the Talos raw image (`<datastore>:iso/<file_name>`) to import into the VM disk over SSH."
  type        = string
}

variable "master_nodes" {
  description = "Map of master nodes: name -> { ip, node } (node is the physical Proxmox node)."
  type = map(object({
    ip   = string
    node = string
  }))
}

variable "worker_nodes" {
  description = "Map of worker nodes: name -> { ip, node } (node is the physical Proxmox node)."
  type = map(object({
    ip   = string
    node = string
  }))
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  type    = number
  default = 0
}

variable "master_vm_id_base" {
  type    = number
  default = 400
}

variable "worker_vm_id_base" {
  type    = number
  default = 500
}

variable "master_resources" {
  type = object({
    vcpu   = number
    memory = number
    disk   = number
  })
  default = { vcpu = 4, memory = 8192, disk = 50 }
}

variable "worker_resources" {
  type = object({
    vcpu   = number
    memory = number
    disk   = number
  })
  default = { vcpu = 8, memory = 16384, disk = 100 }
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "node_prefix" {
  description = "CIDR prefix of the node subnet (e.g. 24 for a /24). Used to build each node's static IP in the cloud-init NoCloud ip_config."
  type        = number
  default     = 24
}

variable "node_gateway" {
  description = "Default gateway for the Kubernetes nodes (static IP routing via cloud-init NoCloud)."
  type        = string
  default     = "192.168.15.1"
}

variable "cloudinit_datastore_id" {
  description = "Proxmox datastore where the cloud-init drive (NoCloud) is created. Must support the `cloudinit` content type (`local-lvm` lvmthin does on PVE 9)."
  type        = string
  default     = "local-lvm"
}

variable "cluster_name" {
  type    = string
  default = "k8s-homelab"
}
