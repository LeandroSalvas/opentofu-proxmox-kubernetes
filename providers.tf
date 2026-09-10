provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_user
  password = var.proxmox_password
  insecure = var.proxmox_insecure

  # Used to import the Talos image (content_type = "iso") into VM disks
  # (file_id path runs `pvesm path` + `qm disk import` on the node).
  ssh {
    agent        = true
    agent_socket = var.proxmox_ssh_agent_socket
    username     = var.proxmox_ssh_username
  }
}

# Helm and Kubernetes providers authenticate with the in-memory client
# configuration exported by the Talos bootstrap (talos_cluster_kubeconfig).
# These attributes are computed, so the provider configuration is unknown at
# plan time and OpenTofu defers loading the provider until the kubeconfig is
# actually generated during apply. This avoids validating ./kubeconfig.yaml at
# plan time, so a greenfield/destroyed state plans cleanly without a placeholder
# file.
provider "helm" {
  kubernetes = {
    host                   = module.bootstrap.kubeconfig_host
    cluster_ca_certificate = module.bootstrap.kubeconfig_ca_certificate
    client_certificate     = module.bootstrap.kubeconfig_client_certificate
    client_key             = module.bootstrap.kubeconfig_client_key
  }
}

# Kubernetes provider (same client config) used by the CAPI module to create the
# provider variables Secret consumed by the Cluster API Operator. The
# local_sensitive_file.kubeconfig stays on disk only for kubectl and the CAPI
# destroy-time cleanup.
provider "kubernetes" {
  host                   = module.bootstrap.kubeconfig_host
  cluster_ca_certificate = module.bootstrap.kubeconfig_ca_certificate
  client_certificate     = module.bootstrap.kubeconfig_client_certificate
  client_key             = module.bootstrap.kubeconfig_client_key
}
