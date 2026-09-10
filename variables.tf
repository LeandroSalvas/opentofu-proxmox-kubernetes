variable "proxmox_api_url" {
  description = "Proxmox VE API endpoint (hostname:port of the API)."
  type        = string
  default     = "https://pve.homelab.salvas:8006"
}

variable "proxmox_user" {
  description = "Proxmox VE user (user@realm). If empty, falls back to env PROXMOX_VE_USERNAME."
  type        = string
  default     = "terraform-prov@pve"
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox VE password. Prefer env PROXMOX_VE_PASSWORD. Never hardcode in committed files."
  type        = string
  default     = ""
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed cert on the homelab)."
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "System user used by the provider to SSH into the PVE nodes (needs root/sudo to import the Talos image)."
  type        = string
  default     = "root"
}

variable "proxmox_ssh_agent_socket" {
  description = "Path to the SSH agent socket used to authenticate the provider's SSH connection (file_id image import). Empty = rely on SSH_AUTH_SOCK."
  type        = string
  default     = "/tmp/opencode/ssh-agent.sock"
}

variable "talos_image_file_name" {
  description = "Filename (post-decompression) of the Talos image in each node's `iso` content directory. PVE rejects .raw extensions; use .img."
  type        = string
  default     = "talos-nocloud-amd64.img"
}

variable "master_count" {
  description = "Number of Kubernetes control plane (master) nodes. Limited to 5 because only IPs .220-.224 are reserved for masters."
  type        = number
  default     = 3

  validation {
    condition     = var.master_count >= 1 && var.master_count <= 5
    error_message = "master_count must be between 1 and 5 (IP range 192.168.15.220-224 reserved for masters)."
  }
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes. Limited to 26 because workers start at IP .225 up to .250."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0 && var.worker_count <= 26
    error_message = "worker_count must be between 0 and 26 (IP range 192.168.15.225-250 for workers)."
  }
}

variable "node_cidr" {
  description = "CIDR of the subnet where the Kubernetes nodes will get their IPs."
  type        = string
  default     = "192.168.15.0/24"
}

variable "master_pool_start" {
  description = "First IP (host octet) of the master pool."
  type        = number
  default     = 220
}

variable "worker_pool_start" {
  description = "First IP (host octet) of the worker pool."
  type        = number
  default     = 225
}

variable "network_bridge" {
  description = "Proxmox network bridge used by all nodes."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag applied to the VMs (0 = no VLAN)."
  type        = number
  default     = 0
}

variable "talos_image_url" {
  description = "URL of the Talos nocloud image (zstd-compressed raw asset from the Image Factory) to download and decompress on each Proxmox node. The nocloud platform delivers machine config + network config at boot via the cloud-init drive, removing the DHCP chicken-and-egg."
  type        = string
  default     = "https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.13.0/nocloud-amd64.raw.zst"
}

variable "talos_image_checksum" {
  description = "Expected sha256 checksum of the Talos image. Note: PVE verifies this against the file as downloaded (compressed .zst) on a fresh download, and against the decompressed file if it already exists. Empty = not verified."
  type        = string
  default     = "daf342f443a9a8cda7103cdae7868ef1c9b791980e3916236dd98b3ee71f274a"
}

variable "vm_datastore_id" {
  description = "Proxmox storage/datastore for the VM disks."
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Proxmox storage/datastore for ISO images (used by the image module)."
  type        = string
  default     = "local"
}

variable "master_vm_ids" {
  description = "Starting VM ID base. Masters get vm_id = master_vm_id_base + index."
  type        = number
  default     = 400
}

variable "min_vm_id" {
  description = "Lower bound for automatically allocated VM IDs."
  type        = number
  default     = 400
}

variable "max_vm_id" {
  description = "Upper bound for automatically allocated VM IDs."
  type        = number
  default     = 999
}

variable "master_resources" {
  description = "Hardware resources for control plane nodes."
  type = object({
    vcpu   = number
    memory = number
    disk   = number
  })
  default = {
    vcpu   = 4
    memory = 8192
    disk   = 50
  }
}

variable "worker_resources" {
  description = "Hardware resources for worker nodes."
  type = object({
    vcpu   = number
    memory = number
    disk   = number
  })
  default = {
    vcpu   = 8
    memory = 16384
    disk   = 100
  }
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for tags/naming)."
  type        = string
  default     = "k8s-homelab"
}

# ---------------------------------------------------------------------------
# Fase 5b - Dynamic, load-aware VM placement
# ---------------------------------------------------------------------------

variable "placement_cpu_weight" {
  description = "Weight of the host CPU utilization in the load score used to pick the least-loaded Proxmox node when creating VMs. Must be between 0 and 1; together with placement_mem_weight it should sum to 1."
  type        = number
  default     = 0.5

  validation {
    condition     = var.placement_cpu_weight >= 0 && var.placement_cpu_weight <= 1
    error_message = "placement_cpu_weight must be between 0 and 1."
  }
}

variable "placement_mem_weight" {
  description = "Weight of the host memory utilization in the load score used to pick the least-loaded Proxmox node when creating VMs. Must be between 0 and 1; together with placement_cpu_weight it should sum to 1."
  type        = number
  default     = 0.5

  validation {
    condition     = var.placement_mem_weight >= 0 && var.placement_mem_weight <= 1
    error_message = "placement_mem_weight must be between 0 and 1."
  }
}

# ---------------------------------------------------------------------------
# Phase 2 - Talos bootstrap
# ---------------------------------------------------------------------------

variable "talos_version" {
  description = "Talos Linux version used to generate the machine configuration."
  type        = string
  default     = "v1.13.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy (must be supported by the chosen Talos version)."
  type        = string
  default     = "v1.36.3"
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint used by Talos (https://<ip>:6443). If empty, it is derived from the first control plane IP."
  type        = string
  default     = ""
}

variable "node_gateway" {
  description = "Default gateway for the Kubernetes nodes (static IP routing)."
  type        = string
  default     = "192.168.15.1"
}

variable "dns_servers" {
  description = "DNS servers for the Talos nodes (static IP implies no DHCP DNS)."
  type        = list(string)
  default     = ["192.168.15.1", "8.8.8.8"]
}

variable "node_interface" {
  description = "Interface name used inside the Talos nodes (virtio NIC on Proxmox -> eth0)."
  type        = string
  default     = "eth0"
}

variable "network_mtu" {
  description = "MTU for the node interface. 0 = let Talos detect the MTU automatically."
  type        = number
  default     = 0
}

variable "install_disk" {
  description = "Disk device where Talos installs itself on each VM."
  type        = string
  default     = "/dev/sda"
}

variable "talos_health_timeout" {
  description = "Timeout for the talos_cluster_health check during plan/refresh."
  type        = string
  default     = "20m"
}

variable "talos_health_skip_kubernetes_checks" {
  description = "If true, only run Talos-level checks (etcd, apid, kubelet, boot) in talos_cluster_health. Required during Fase 3: nodes are NotReady until Cilium takes over the CNI (kube-proxy removed, flannel disabled)."
  type        = bool
  default     = true
}

variable "controlplane_config_patches" {
  description = "Extra YAML patches applied to all control plane machine configs."
  type        = list(string)
  default     = []
}

variable "worker_config_patches" {
  description = "Extra YAML patches applied to all worker machine configs."
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Optional SSH public key added to the nodes (Talos does not use SSH by default; kept for reference/debug)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Phase 3 - Cilium CNI
# ---------------------------------------------------------------------------

variable "cilium_chart_version" {
  description = "Version of the cilium/cilium Helm chart to install."
  type        = string
  default     = "1.20.1"
}

variable "cilium_k8s_service_host" {
  description = "Address of the Kubernetes API server as seen by the Cilium agent (the HAProxy LB in front of the control plane, Fase 3). Must forward TCP 6443 to the control plane nodes."
  type        = string
  default     = "192.168.15.113"
}

variable "cilium_k8s_service_port" {
  description = "Port of the Kubernetes API server as seen by the Cilium agent."
  type        = number
  default     = 6443
}

variable "cilium_extra_values" {
  description = "Extra Helm values (raw YAML) merged over the module defaults."
  type        = list(string)
  default     = []
}

variable "cilium_enable_lb" {
  description = "Enable LoadBalancer services with Cilium LB-IPAM + L2 Announcements (kube-proxy-free). Disable to fall back to manual port-forward/NodePort."
  type        = bool
  default     = true
}

variable "cilium_lb_ipam_cidrs" {
  description = "CIDRs/IP ranges the operator may allocate to LoadBalancer services (CiliumLoadBalancerIPPool). Keep out of your DHCP and existing static ranges."
  type        = list(string)
  default     = ["192.168.15.230-192.168.15.245"]
}

variable "cilium_hubble_ui_enabled" {
  description = "Deploy Hubble Relay + Hubble UI (network service map / dashboards). Defaults to a NodePort service."
  type        = bool
  default     = true
}

variable "cilium_hubble_ui_service_type" {
  description = "Kubernetes Service type for the Hubble UI (ClusterIP, NodePort or LoadBalancer)."
  type        = string
  default     = "NodePort"
}

variable "cilium_hubble_ui_node_port" {
  description = "nodePort for the Hubble UI Service when type is NodePort."
  type        = number
  default     = 31235
}

variable "cilium_hubble_metrics_enabled" {
  description = "Export Hubble flow metrics (dns/drop/tcp/flow/icmp/http) from the agents to power the UI dashboards."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Phase 5 - NFS storage
# ---------------------------------------------------------------------------

variable "nfs_server" {
  description = "Existing NFS server for the k8s storage class (Fase 5)."
  type        = string
  default     = "192.168.15.29"
}

variable "nfs_path" {
  description = "Base path exported by the NFS server for Kubernetes volumes."
  type        = string
  default     = "/NAS/kube_storage"
}

variable "storage_chart_version" {
  description = "Version of the nfs-subdir-external-provisioner Helm chart."
  type        = string
  default     = "4.0.18"
}

variable "storage_class_name" {
  description = "Name of the default StorageClass created by the NFS provisioner."
  type        = string
  default     = "nfs-client"
}

variable "storage_set_default_class" {
  description = "Mark the NFS StorageClass as the cluster default."
  type        = bool
  default     = true
}

variable "storage_namespace" {
  description = "Namespace where the NFS provisioner is installed."
  type        = string
  default     = "kube-system"
}

variable "storage_extra_values" {
  description = "Extra Helm values (raw YAML) merged over the module defaults."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Phase 4 - Cluster API (Cluster API Operator + providers)
# ---------------------------------------------------------------------------

variable "capi_cert_manager_chart_version" {
  description = "Version of the jetstack/cert-manager Helm chart (prerequisite for CAPI webhooks)."
  type        = string
  default     = "1.21.1"
}

variable "capi_operator_chart_version" {
  description = "Version of the cluster-api-operator Helm chart."
  type        = string
  default     = "0.29.0"
}

variable "capi_core_version" {
  description = "Version of the CoreProvider (cluster-api)."
  type        = string
  default     = "v1.12.11"
}

variable "capi_kubeadm_bootstrap_version" {
  description = "Version of the Kubernetes BootstrapProvider (kubeadm)."
  type        = string
  default     = "v1.12.11"
}

variable "capi_kubeadm_control_plane_version" {
  description = "Version of the Kubernetes ControlPlaneProvider (kubeadm)."
  type        = string
  default     = "v1.12.11"
}

variable "capi_proxmox_provider_version" {
  description = "Version of the InfrastructureProvider (cluster-api-provider-proxmox / CAPMOX)."
  type        = string
  default     = "v0.9.1"
}

variable "capi_in_cluster_ipam_version" {
  description = "Version of the IPAMProvider (in-cluster ipam)."
  type        = string
  default     = "v1.1.0"
}

variable "capi_config_secret_name" {
  description = "Name of the Secret holding clusterctl variables for the CAPMOX provider."
  type        = string
  default     = "clusterctl-vars"
}

variable "capi_config_secret_namespace" {
  description = "Namespace of the CAPMOX clusterctl variables Secret."
  type        = string
  default     = "capmox-system"
}

variable "capi_proxmox_url" {
  description = "Proxmox VE API URL used by CAPMOX (must be reachable from inside the cluster)."
  type        = string
  sensitive   = true
}

variable "capi_proxmox_token" {
  description = "Proxmox API token ID (user@realm!tokenid), e.g. terraform-prov@pve!capi."
  type        = string
  sensitive   = true
}

variable "capi_proxmox_secret" {
  description = "Proxmox API token secret (UUID returned when the token was created)."
  type        = string
  sensitive   = true
}

variable "capi_extra_values" {
  description = "Extra Helm values (raw YAML) merged over the CAPI module defaults."
  type        = list(string)
  default     = []
}
