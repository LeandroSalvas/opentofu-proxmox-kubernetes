output "namespace" {
  value       = helm_release.kubernetes_dashboard.namespace
  description = "Namespace where the Kubernetes Dashboard is installed."
}

output "admin_service_account" {
  value       = kubernetes_service_account_v1.dashboard_admin.metadata[0].name
  description = "ServiceAccount whose tokens unlock the dashboard."
}