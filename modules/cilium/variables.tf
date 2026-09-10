variable "chart_version" {
  description = "Version of the cilium/cilium Helm chart."
  type        = string
}

variable "k8s_service_host" {
  description = "Address of the Kubernetes API server seen by the Cilium agent (HAProxy LB in front of the control plane)."
  type        = string
}

variable "k8s_service_port" {
  description = "Port of the Kubernetes API server seen by the Cilium agent."
  type        = number
}

variable "control_plane_taint" {
  description = "Control plane taint key that cilium-agent and cilium-operator must tolerate."
  type        = string
  default     = "node-role.kubernetes.io/control-plane"
}

variable "extra_values" {
  description = "Raw YAML values merged over the module defaults (later overrides earlier)."
  type        = list(string)
  default     = []
}

variable "namespace" {
  description = "Namespace where Cilium is installed."
  type        = string
  default     = "kube-system"
}

variable "enable_lb" {
  description = "Enable LoadBalancer services via Cilium LB-IPAM + L2 Announcements (kube-proxy-free)."
  type        = bool
  default     = true
}

variable "lb_ipam_cidrs" {
  description = "CIDRs/IP ranges (strings) that the operator may allocate to LoadBalancer services. Keep them out of your DHCP/LAN static ranges."
  type        = list(string)
  default     = []
}

variable "hubble_ui_enabled" {
  description = "Deploy Hubble Relay + Hubble UI (network service map / dashboards) on top of the agents."
  type        = bool
  default     = true
}

variable "hubble_ui_service_type" {
  description = "Kubernetes Service type for the Hubble UI (ClusterIP, NodePort or LoadBalancer)."
  type        = string
  default     = "NodePort"
}

variable "hubble_ui_node_port" {
  description = "nodePort for the Hubble UI Service when type is NodePort."
  type        = number
  default     = 31235
}

variable "hubble_metrics_enabled" {
  description = "Export Hubble flow metrics (dns/drop/tcp/flow/icmp/http) from the agents on port 9965 to power the UI dashboards."
  type        = bool
  default     = true
}
