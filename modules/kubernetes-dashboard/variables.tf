variable "chart_version" {
  description = "Version of the kubernetes-dashboard/kubernetes-dashboard Helm chart."
  type        = string
}

variable "namespace" {
  description = "Namespace where the Kubernetes Dashboard is installed."
  type        = string
  default     = "kubernetes-dashboard"
}

variable "service_type" {
  description = "Kubernetes Service type for the dashboard gateway (kong-proxy): ClusterIP, NodePort or LoadBalancer."
  type        = string
  default     = "NodePort"
}

variable "node_port" {
  description = "nodePort for the dashboard gateway when type is NodePort (HTTPS)."
  type        = number
  default     = 30443
}

variable "metrics_server_enabled" {
  description = "Deploy the bundled metrics-server subchart so the dashboard renders CPU/memory charts."
  type        = bool
  default     = true
}

variable "extra_values" {
  description = "Raw YAML values merged over the module defaults (later overrides earlier)."
  type        = list(string)
  default     = []
}