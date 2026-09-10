output "master_vms" {
  description = "Map of control plane VM names -> { id, node, ip }."
  value = {
    for name, vm in proxmox_virtual_environment_vm.master :
    name => {
      id   = vm.vm_id
      node = vm.node_name
      ip   = var.master_nodes[name].ip
    }
  }
}

output "worker_vms" {
  description = "Map of worker VM names -> { id, node, ip }."
  value = {
    for name, vm in proxmox_virtual_environment_vm.worker :
    name => {
      id   = vm.vm_id
      node = vm.node_name
      ip   = var.worker_nodes[name].ip
    }
  }
}
