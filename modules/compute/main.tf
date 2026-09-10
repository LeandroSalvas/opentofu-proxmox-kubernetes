resource "proxmox_virtual_environment_vm" "master" {
  for_each = var.master_nodes

  name        = each.key
  description = "Kubernetes control plane node ${each.value.ip}"
  node_name   = each.value.node
  vm_id       = var.master_vm_id_base + tonumber(regex("KuM(\\d+)", each.key)[0]) - 1

  tags = toset([
    var.cluster_name,
    "k8s",
    "controlplane",
  ])

  started = true
  on_boot = true

  cpu {
    cores = var.master_resources.vcpu
    type  = "host"
  }

  memory {
    dedicated = var.master_resources.memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = var.master_resources.disk
    file_format  = "raw"
    file_id      = var.talos_image_file_id
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id > 0 ? var.vlan_id : null
  }

  # NoCloud drive: static IP delivered at first boot via cloud-init, so DHCP
  # is never needed and the node is always reachable at its reserved address.
  initialization {
    datastore_id = var.cloudinit_datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.node_prefix}"
        gateway = var.node_gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = var.worker_nodes

  name        = each.key
  description = "Kubernetes worker node ${each.value.ip}"
  node_name   = each.value.node
  vm_id       = var.worker_vm_id_base + tonumber(regex("KuMn(\\d+)", each.key)[0]) - 1

  tags = toset([
    var.cluster_name,
    "k8s",
    "worker",
  ])

  started = true
  on_boot = true

  cpu {
    cores = var.worker_resources.vcpu
    type  = "host"
  }

  memory {
    dedicated = var.worker_resources.memory
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = var.worker_resources.disk
    file_format  = "raw"
    file_id      = var.talos_image_file_id
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id > 0 ? var.vlan_id : null
  }

  initialization {
    datastore_id = var.cloudinit_datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.node_prefix}"
        gateway = var.node_gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }
}
