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