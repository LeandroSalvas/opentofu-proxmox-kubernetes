# Provider config is inherited from the root terraform (helm provider bound to
# the generated kubeconfig), so no provider block is needed here.

locals {
  merged_values = concat([
    yamlencode({
      nfs = {
        server = var.nfs_server
        path   = var.nfs_path
      }
      storageClass = {
        create       = true
        name         = var.storage_class_name
        defaultClass = var.set_default_storage_class
      }
    })
  ], var.extra_values)
}

resource "helm_release" "nfs" {
  name             = "nfs-subdir-external-provisioner"
  namespace        = var.namespace
  create_namespace = false

  repository       = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart            = "nfs-subdir-external-provisioner"
  version          = var.chart_version

  values = local.merged_values
}