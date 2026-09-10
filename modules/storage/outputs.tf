output "release_name" {
  description = "Name of the installed NFS provisioner Helm release."
  value       = helm_release.nfs.name
}

output "release_namespace" {
  description = "Namespace where the provisioner is installed."
  value       = helm_release.nfs.namespace
}

output "release_version" {
  description = "Installed provisioner chart version."
  value       = helm_release.nfs.version
}