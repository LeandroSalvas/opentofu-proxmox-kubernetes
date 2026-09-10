variable "cert_manager_chart_version" {
  description = "Version of the jetstack/cert-manager Helm chart (prerequisite for CAPI webhooks)."
  type        = string
  default     = "1.21.1"
}

variable "operator_chart_version" {
  description = "Version of the cluster-api-operator Helm chart."
  type        = string
  default     = "0.29.0"
}

variable "core_version" {
  description = "Version of the CoreProvider (cluster-api) installed by the Operator."
  type        = string
  default     = "v1.12.11"
}

variable "kubeadm_bootstrap_version" {
  description = "Version of the Kubernetes BootstrapProvider (kubeadm)."
  type        = string
  default     = "v1.12.11"
}

variable "kubeadm_control_plane_version" {
  description = "Version of the Kubernetes ControlPlaneProvider (kubeadm)."
  type        = string
  default     = "v1.12.11"
}

variable "proxmox_provider_version" {
  description = "Version of the InfrastructureProvider (cluster-api-provider-proxmox / CAPMOX)."
  type        = string
  default     = "v0.9.1"
}

variable "in_cluster_ipam_version" {
  description = "Version of the IPAMProvider (in-cluster ipam)."
  type        = string
  default     = "v1.1.0"
}

variable "provider_config_secret_name" {
  description = "Name of the Secret holding clusterctl variables injected by the Operator."
  type        = string
  default     = "clusterctl-vars"
}

variable "provider_config_secret_namespace" {
  description = "Namespace of the clusterctl variables Secret (must match what the provider CRs reference)."
  type        = string
  default     = "capmox-system"
}

variable "proxmox_url" {
  description = "Proxmox VE API URL used by CAPMOX (PROXMOX_URL env). Must be reachable from inside the cluster."
  type        = string
  sensitive   = true
}

variable "proxmox_token" {
  description = "Proxmox API token ID (user@realm!tokenid), e.g. terraform-prov@pve!capi."
  type        = string
  sensitive   = true
}

variable "proxmox_secret" {
  description = "Proxmox API token secret (UUID returned when the token was created)."
  type        = string
  sensitive   = true
}

variable "extra_values" {
  description = "Raw YAML values merged over the module defaults (later overrides earlier)."
  type        = list(string)
  default     = []
}

variable "kubeconfig_path" {
  description = "Filesystem path to the kubeconfig used to reach the cluster (for the destroy-time CR cleanup)."
  type        = string
}