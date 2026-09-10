variable "chart_version" {
  description = "Version of the nfs-subdir-external-provisioner Helm chart."
  type        = string
}

variable "namespace" {
  description = "Namespace where the provisioner is installed."
  type        = string
  default     = "kube-system"
}

variable "nfs_server" {
  description = "IP or hostname of the existing NFS server."
  type        = string
}

variable "nfs_path" {
  description = "Base path exported by the NFS server (subdirectories are created per PVC)."
  type        = string
}

variable "storage_class_name" {
  description = "Name of the StorageClass created by the provisioner."
  type        = string
  default     = "nfs-client"
}

variable "set_default_storage_class" {
  description = "Make this StorageClass the cluster default (annotate storageclass.kubernetes.io/is-default-class: true)."
  type        = bool
  default     = true
}

variable "extra_values" {
  description = "Raw YAML values merged over the module defaults (later overrides earlier)."
  type        = list(string)
  default     = []
}