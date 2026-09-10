variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster."
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint used by Talos (https://<ip>:6443)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy."
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version used to generate the machine configuration."
  type        = string
}

variable "controlplane_nodes" {
  description = "Map of control plane node name -> static IP (e.g. KuM1 -> 192.168.15.220)."
  type        = map(string)
}

variable "worker_nodes" {
  description = "Map of worker node name -> static IP (e.g. KuMn1 -> 192.168.15.225)."
  type        = map(string)
}

variable "gateway" {
  description = "Default gateway for the nodes."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for the nodes."
  type        = list(string)
}

variable "node_prefix" {
  description = "Subnet prefix length (e.g. 24 for /24)."
  type        = number
}

variable "network_interface" {
  description = "Interface name inside Talos (virtio NIC -> eth0)."
  type        = string
  default     = "eth0"
}

variable "network_mtu" {
  description = "MTU for the node interface. 0 = automatic detection."
  type        = number
  default     = 0
}

variable "install_disk" {
  description = "Disk device where Talos installs itself."
  type        = string
  default     = "/dev/sda"
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

variable "health_timeout" {
  description = "Timeout for the cluster health check data source."
  type        = string
  default     = "20m"
}

variable "skip_kubernetes_checks" {
  description = "If true, the health check only validates Talos-level services (etcd, apid, kubelet, boot sequence) and skips Kubernetes readiness. Needed while Cilium takes over the CNI."
  type        = bool
  default     = false
}