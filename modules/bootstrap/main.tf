# ---------------------------------------------------------------------------
# Cluster identity: one set of secrets (CA + cluster tokens) shared by every
# node. Kept in Terraform state (sensitive) so re-runs are idempotent.
# ---------------------------------------------------------------------------
resource "talos_machine_secrets" "this" {}

locals {
  # IPs ordered by node number, not lexicographically: `sort(names)` would
  # place KuW10 before KuW2. We extract the trailing number of each name and
  # order by it, so controlplane = KuM1, KuM2, ... and workers = KuW1, KuW2, ...
  # The first control-plane entry is the bootstrap node.
  controlplane_num_ip = {
    for name, ip in var.controlplane_nodes :
    tonumber(regex("[A-Za-z]+([0-9]+)$", name)[0]) => ip
  }
  worker_num_ip = {
    for name, ip in var.worker_nodes :
    tonumber(regex("[A-Za-z]+([0-9]+)$", name)[0]) => ip
  }
  controlplane_ips = [for n in sort(keys(local.controlplane_num_ip)) : local.controlplane_num_ip[n]]
  worker_ips       = [for n in sort(keys(local.worker_num_ip)) : local.worker_num_ip[n]]

  bootstrap_node_ip = local.controlplane_ips[0]

  # Base interface map. `mtu` is stripped by the null filter when it is 0
  # (automatic detection), so the generated YAML never contains `mtu: null`.
  interface_base = {
    interface = var.network_interface
    addresses = []
    routes = [
      {
        network = "0.0.0.0/0"
        gateway = var.gateway
      }
    ]
    mtu = var.network_mtu > 0 ? var.network_mtu : null
  }

  # interface_configs[ip] = final interface map for that node (nulls removed).
  interface_configs = {
    for ip in concat(local.controlplane_ips, local.worker_ips) :
    ip => {
      for k, v in merge(local.interface_base, { addresses = ["${ip}/${var.node_prefix}"] }) :
      k => v if v != null
    }
  }

  # Per-node patch: static IP + default route + DNS + install disk.
  # This is applied at bootstrap time, converting the DHCP/maintenance boot
  # into a deterministic static network configuration. The hostname is NOT set
  # here: on Talos v1.13+ (multidoc network config) it must be configured via
  # the separate HostnameConfig document (see hostname_patches below), otherwise
  # it conflicts with the auto-generated `auto: stable` HostnameConfig.
  node_patches = merge(
    {
      for name, ip in var.controlplane_nodes :
      ip => yamlencode({
        machine = {
          network = {
            interfaces  = [local.interface_configs[ip]]
            nameservers = var.dns_servers
          }
          install = {
            disk = var.install_disk
          }
        }
      })
    },
    {
      for name, ip in var.worker_nodes :
      ip => yamlencode({
        machine = {
          network = {
            interfaces  = [local.interface_configs[ip]]
            nameservers = var.dns_servers
          }
          install = {
            disk = var.install_disk
          }
        }
      })
    }
  )

  # Per-node HostnameConfig document patch (Talos v1.13+ multidoc network
  # config): replaces the generated `auto: stable` with a static hostname.
  # Keyed by IP to match node_patches.
  hostname_patches = merge(
    {
      for name, ip in var.controlplane_nodes :
      ip => yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        auto       = "off"
        hostname   = name
      })
    },
    {
      for name, ip in var.worker_nodes :
      ip => yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        auto       = "off"
        hostname   = name
      })
    }
  )
}

# ---------------------------------------------------------------------------
# Machine configurations (control plane + worker), generated from the shared
# secrets. Common patches (extra user patches) are baked in here.
# ---------------------------------------------------------------------------
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches     = var.controlplane_config_patches
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  docs               = false
  examples           = false
  config_patches     = var.worker_config_patches
}

# ---------------------------------------------------------------------------
# Apply the machine configurations to each node while it is in maintenance
# mode. The per-node network/install patch is merged on top of the shared
# config, so every node ends up with its own static IP and hostname.
# ---------------------------------------------------------------------------
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.controlplane_nodes

  node                        = each.value
  endpoint                    = each.value
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  config_patches              = [local.node_patches[each.value], local.hostname_patches[each.value]]
  apply_mode                  = "auto"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  node                        = each.value
  endpoint                    = each.value
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  config_patches              = [local.node_patches[each.value], local.hostname_patches[each.value]]
  apply_mode                  = "auto"
}

# ---------------------------------------------------------------------------
# Bootstrap etcd on the first control plane node (equivalent of
# `talosctl bootstrap`) via the Talos API. The other control planes join as
# etcd members once they have their configurations applied.
# ---------------------------------------------------------------------------
resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.controlplane,
    talos_machine_configuration_apply.worker,
  ]

  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# ---------------------------------------------------------------------------
# Wait until the full cluster (etcd + kubelet + Kubernetes components) is
# healthy, then fetch the kubeconfig.
# ---------------------------------------------------------------------------
data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = local.controlplane_ips
  worker_nodes         = local.worker_ips
  endpoints            = local.controlplane_ips

  skip_kubernetes_checks = var.skip_kubernetes_checks

  timeouts = {
    read = var.health_timeout
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  node                 = local.bootstrap_node_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# talosconfig for talosctl (nodes + endpoints pre-configured).
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = concat(local.controlplane_ips, local.worker_ips)
}