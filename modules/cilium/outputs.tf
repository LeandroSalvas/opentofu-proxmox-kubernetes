output "release_name" {
  description = "Name of the installed Cilium Helm release."
  value       = helm_release.cilium.name
}

output "release_namespace" {
  description = "Namespace where Cilium is installed."
  value       = helm_release.cilium.namespace
}

output "release_version" {
  description = "Installed Cilium chart version."
  value       = helm_release.cilium.version
}