# ---------------------------------------------------------------------------
# Node-aware discovery: detect online Proxmox nodes dynamically.
# Works for both single-node and multi-node clusters (no hardcoded node names).
# The `names` and `online` lists are parallel: index i of `names` matches
# index i of `online`.
# ---------------------------------------------------------------------------
data "proxmox_virtual_environment_nodes" "cluster" {}

# Per-host status (utilization, memory) used to score live placement. Only
# online nodes are queried; the aggregates above provide the online filter.
data "proxmox_virtual_environment_node" "status" {
  for_each = toset(local.online_nodes)

  node_name = each.key
}

locals {
  # Physical Proxmox nodes that are online right now.
  online_nodes = [
    for i, name in data.proxmox_virtual_environment_nodes.cluster.names :
    name
    if data.proxmox_virtual_environment_nodes.cluster.online[i]
  ]

  online_nodes_sorted = sort(local.online_nodes)
  node_count          = length(local.online_nodes_sorted)

  # -------------------------------------------------------------------------
  # Dynamic, load-aware VM placement.
  #
  # Each online host is scored by its CURRENT utilization (CPU + memory, both
  # clamped to [0,1]) and new VMs are distributed over a weighted ring where a
  # host appears in proportion to its free headroom. The ring is deterministic
  # for a given load snapshot: ties are broken by node name.
  #
  # Existing VMs are never migrated: the compute module keeps node_name under
  # lifecycle.ignore_changes, so this only affects VMs *created* on the next
  # apply (scale-out or re-provisioning), not the ones already running.
  # -------------------------------------------------------------------------
  node_cpu_util = {
    for n in local.online_nodes_sorted :
    n => min(data.proxmox_virtual_environment_node.status[n].cpu_utilization, 1)
  }

  node_mem_util = {
    for n in local.online_nodes_sorted :
    n => (
      data.proxmox_virtual_environment_node.status[n].memory_total > 0
      ? min(
        1,
        data.proxmox_virtual_environment_node.status[n].memory_used /
        data.proxmox_virtual_environment_node.status[n].memory_total,
      )
      : 0
    )
  }

  # Weighted utilization score [0,1]: higher = busier host. Weights are
  # normalized so any values (even 0/0 edge cases) behave deterministically.
  placement_weight_total = max(var.placement_cpu_weight + var.placement_mem_weight, 0.0001)

  node_score = {
    for n in local.online_nodes_sorted :
    n => (
      (var.placement_cpu_weight / local.placement_weight_total) * local.node_cpu_util[n] +
      (var.placement_mem_weight / local.placement_weight_total) * local.node_mem_util[n]
    )
  }

  # Free headroom [0.01, 1]; every online node stays eligible to receive VMs.
  node_free = {
    for n in local.online_nodes_sorted :
    n => max(1 - local.node_score[n], 0.01)
  }

  node_free_total = max(sum([for n in local.online_nodes_sorted : local.node_free[n]]), 0.0001)

  # Least-loaded first; deterministic tie-break by node name.
  node_order = [
    for entry in sort([
      for n in local.online_nodes_sorted :
      format("%.6f|%s", local.node_score[n], n)
    ]) :
    split("|", entry)[1]
  ]

  # Slot count per host proportional to its headroom (scale K=10). OpenTofu has
  # no round(); floor(x + 0.5) is the equivalent.
  node_slots = {
    for n in local.online_nodes_sorted :
    n => max(1, floor(10 * local.node_free[n] / local.node_free_total + 0.5))
  }

  max_slots = max([for n in local.online_nodes_sorted : local.node_slots[n]]...)

  # Ring built one "round" per slot position: each round takes one slot from
  # every host that still has slots left (least-loaded first). Interleaving
  # keeps the exact proportional totals while preventing consecutive VMs from
  # clumping onto a single host.
  placement_ring = concat([
    for s in range(local.max_slots) :
    [for n in local.node_order : n if s < local.node_slots[n]]
  ]...)

  # Kubernetes master and worker IPs derived from the pool.
  # Masters: .220 + i (i = 0..master_count-1) -> up to 5 (.220-.224)
  # Workers: .225 + i (i = 0..worker_count-1)   -> up to 26 (.225-.250)
  master_ips = [
    for i in range(var.master_count) :
    cidrhost(var.node_cidr, var.master_pool_start + i)
  ]
  worker_ips = [
    for i in range(var.worker_count) :
    cidrhost(var.node_cidr, var.worker_pool_start + i)
  ]

  # Dynamic placement: each K8s node walks the weighted ring (masters first,
  # then workers), so the heavier/further VMs land on the least-loaded hosts.
  # With 1 node: the whole ring is that single node.
  master_nodes = {
    for i in range(var.master_count) :
    "KuM${i + 1}" => {
      ip   = local.master_ips[i]
      node = local.placement_ring[i % length(local.placement_ring)]
    }
  }

  worker_nodes = {
    for i in range(var.worker_count) :
    "KuW${i + 1}" => {
      ip   = local.worker_ips[i]
      node = local.placement_ring[(var.master_count + i) % length(local.placement_ring)]
    }
  }

  # Phase 2 helpers: name -> IP maps for the Talos bootstrap, plus derived
  # cluster endpoint and subnet prefix.
  master_ips_map = { for name, v in local.master_nodes : name => v.ip }
  worker_ips_map = { for name, v in local.worker_nodes : name => v.ip }

  first_master_ip = local.master_nodes[sort(keys(local.master_nodes))[0]].ip

  cluster_endpoint = var.cluster_endpoint != "" ? var.cluster_endpoint : "https://${local.first_master_ip}:6443"

  node_prefix = tonumber(split("/", var.node_cidr)[1])

  # Fase 3: replace the built-in flannel CNI + kube-proxy with Cilium in
  # kube-proxy-free mode (kubeProxyReplacement strict).
  #
  # cluster.network.cni.name=none  -> Talos stops managing flannel
  # cluster.proxy.disabled=true    -> Talos stops deploying kube-proxy
  # machine.features.hostDNS.forwardKubeDNSToHost=false -> avoids the known
  #   CoreDNS breakage when Cilium bpf.masquerade=true (Talos #9200).
  #
  # Talos applies cluster-scope changes immediately (no node reboot), so all
  # nodes get the new config in place and Cilium takes over the CNI.
  #
  # Control-plane only: add the load-balancer IP (192.168.15.113) to the
  # kube-apiserver certificate SANs. Cilium reaches the cluster via the LB
  # (k8sServiceHost), so the apiserver cert must be valid for that address.
  # This is additive: the bootstrap endpoint (.220) is always included via
  # k8sRoot.Endpoint independently of CertSANs.
  apiserver_cert_san_patch = yamlencode({
    cluster = {
      apiServer = {
        certSANs = [var.cilium_k8s_service_host]
      }
    }
  })

  cilium_cni_patch = yamlencode({
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
    machine = {
      features = {
        hostDNS = {
          forwardKubeDNSToHost = false
        }
      }
    }
  })
}

# ---------------------------------------------------------------------------
# FASE 1: Download and decompress the Talos nocloud image into the node-local
# storage `iso` content directory on EVERY online node (storage `local` is
# node-local and VMs are round-robined across nodes). PVE only decompresses
# server-side for the `iso` content type, so we use content_type="iso" + zst.
# ---------------------------------------------------------------------------
module "image" {
  source = "./modules/image"

  proxmox_nodes        = toset(local.online_nodes_sorted)
  iso_datastore_id     = var.iso_datastore_id
  talos_image_url      = var.talos_image_url
  talos_image_checksum = var.talos_image_checksum
  image_file_name      = var.talos_image_file_name
}

# ---------------------------------------------------------------------------
# FASE 1: Create the control plane (masters) and worker VMs, distributed
# load-aware across the online Proxmox nodes (weighted by current free
# headroom; see the placement locals above). Each disk imports the local
# Talos image over SSH (file_id). Existing VMs keep their node (ignore_changes
# in the compute module), so this placement only drives new creations.
# ---------------------------------------------------------------------------
module "compute" {
  source     = "./modules/compute"
  depends_on = [module.image]

  online_nodes        = local.online_nodes_sorted
  talos_image_file_id = module.image.file_volume_id

  master_nodes = local.master_nodes
  worker_nodes = local.worker_nodes

  network_bridge    = var.network_bridge
  vlan_id           = var.vlan_id
  master_vm_id_base = var.master_vm_ids
  worker_vm_id_base = var.master_vm_ids + var.master_count

  master_resources = var.master_resources
  worker_resources = var.worker_resources
  vm_datastore_id  = var.vm_datastore_id
  cluster_name     = var.cluster_name

  node_prefix            = local.node_prefix
  node_gateway           = var.node_gateway
  cloudinit_datastore_id = var.vm_datastore_id
}

# ---------------------------------------------------------------------------
# Wait for the Talos API (port 50000) to become reachable on every node
# before attempting to apply machine configuration.  Polls each IP with
# a 5-second interval and a 5-minute per-node timeout.
# ---------------------------------------------------------------------------
resource "terraform_data" "wait_for_talos_api" {
  depends_on = [module.compute]

  input = join(" ", concat(
    [for k, v in local.master_ips_map : v],
    [for k, v in local.worker_ips_map : v],
  ))

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      for ip in ${self.input}; do
        echo "Waiting for Talos API on $ip:50000..."
        timeout 300 bash -c "until echo > /dev/tcp/$ip/50000 2>/dev/null; do sleep 5; done"
        echo "$ip:50000 ready"
      done
    EOT
  }
}

# ---------------------------------------------------------------------------
# FASE 2: Bootstrap the immutable Talos cluster.
# Generates machine configs (control plane + worker), applies them to the
# nodes, bootstraps etcd (`talosctl bootstrap` equivalent) via the Talos API,
# and extracts the kubeconfig once the cluster is healthy.
# No SSH: everything happens over the Talos API (ports 50000/50061/6443).
# ---------------------------------------------------------------------------
module "bootstrap" {
  source     = "./modules/bootstrap"
  depends_on = [terraform_data.wait_for_talos_api]

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version

  controlplane_nodes = local.master_ips_map
  worker_nodes       = local.worker_ips_map

  gateway           = var.node_gateway
  dns_servers       = var.dns_servers
  node_prefix       = local.node_prefix
  network_interface = var.node_interface
  network_mtu       = var.network_mtu
  install_disk      = var.install_disk

  controlplane_config_patches = concat(var.controlplane_config_patches, [local.cilium_cni_patch, local.apiserver_cert_san_patch])
  worker_config_patches       = concat(var.worker_config_patches, [local.cilium_cni_patch])
  health_timeout              = var.talos_health_timeout
  skip_kubernetes_checks      = var.talos_health_skip_kubernetes_checks
}

# ---------------------------------------------------------------------------
# Persist the kubeconfig to disk so the helm provider (and kubectl) can talk
# to the cluster. The helm provider references config_path above. Sensitive
# file: written with 0600 permissions.
# ---------------------------------------------------------------------------
resource "local_sensitive_file" "kubeconfig" {
  filename        = "${path.module}/kubeconfig.yaml"
  content         = module.bootstrap.kubeconfig_raw
  file_permission = "0600"
}

# ---------------------------------------------------------------------------
# Label the Kubernetes worker nodes with their role. Applied right after the
# cluster is healthy (module.bootstrap, when every node already exists), so
# `kubectl get nodes` shows ROLES=worker and selectors like
# node-role.kubernetes.io/worker= work for any worker_count.
# ---------------------------------------------------------------------------
resource "kubernetes_labels" "worker" {
  for_each = { for name in sort(keys(local.worker_nodes)) : lower(name) => name }

  api_version = "v1"
  kind        = "Node"
  metadata {
    name = each.key
  }
  labels = {
    "node-role.kubernetes.io/worker" = ""
  }

  depends_on = [module.bootstrap]
}

# ---------------------------------------------------------------------------
# FASE 3: Cilium CNI (kube-proxy-free).
# Installed via Helm against the kubeconfig above once the cluster is healthy.
# Requires the LB (192.168.15.113) to already forward 6443 -> control plane
# (see infra/lb/haproxy-k8s-api.cfg), otherwise Cilium agents cannot reach the
# API server and the nodes never become Ready.
# ---------------------------------------------------------------------------
module "cilium" {
  source = "./modules/cilium"

  k8s_service_host       = var.cilium_k8s_service_host
  k8s_service_port       = var.cilium_k8s_service_port
  chart_version          = var.cilium_chart_version
  control_plane_taint    = "node-role.kubernetes.io/control-plane"
  extra_values           = var.cilium_extra_values
  enable_lb              = var.cilium_enable_lb
  lb_ipam_cidrs          = var.cilium_lb_ipam_cidrs
  hubble_ui_enabled      = var.cilium_hubble_ui_enabled
  hubble_ui_service_type = var.cilium_hubble_ui_service_type
  hubble_ui_node_port    = var.cilium_hubble_ui_node_port
  hubble_metrics_enabled = var.cilium_hubble_metrics_enabled

  depends_on = [module.bootstrap]
}

# ---------------------------------------------------------------------------
# FASE 3b: LoadBalancer services via Cilium (LB-IPAM + L2 Announcements).
#
# The cilium-operator registers the CiliumL2AnnouncementPolicy CRD only once
# the agent runs with l2announcements enabled, so the helm upgrade must finish
# and the CRD must be established before the manifests below are applied.
# Services with `type: LoadBalancer` then get an IP from cilium_lb_ipam_cidrs
# and are announced over the LAN on eth0 (ARP/L2, kube-proxy-free).
# ---------------------------------------------------------------------------
resource "terraform_data" "cilium_lb_agent_restart" {
  count = var.cilium_enable_lb ? 1 : 0

  triggers_replace = timestamp()

  # The Cilium daemonset template does not carry a config checksum, so a helm
  # upgrade that flips enable-l2-announcements only lands in the ConfigMap; the
  # agents must be rolled out to actually pick it up. The restart is idempotent
  # and cheap, so run it on every apply before creating the LB CRs.
  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${local_sensitive_file.kubeconfig.filename} -n kube-system rollout restart daemonset/cilium && kubectl --kubeconfig ${local_sensitive_file.kubeconfig.filename} -n kube-system rollout status daemonset/cilium --timeout=300s"
  }

  depends_on = [module.cilium]
}

resource "terraform_data" "cilium_lb_crd_ready" {
  count = var.cilium_enable_lb ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${local_sensitive_file.kubeconfig.filename} wait --for=condition=established --timeout=180s crd/ciliumloadbalancerippools.cilium.io crd/ciliuml2announcementpolicies.cilium.io"
  }

  depends_on = [terraform_data.cilium_lb_agent_restart]
}

resource "local_file" "cilium_lb_pool_yaml" {
  count    = var.cilium_enable_lb ? 1 : 0
  filename = "${path.module}/.gen/cilium-lb-pool.yaml"
  content = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "lb-pool"
    }
    spec = {
      blocks = [
        for entry in var.cilium_lb_ipam_cidrs : can(regex("-", entry)) ? {
          start = split("-", entry)[0]
          stop  = split("-", entry)[1]
          } : {
          cidr = entry
        }
      ]
    }
  })
}

resource "local_file" "cilium_l2_policy_yaml" {
  count    = var.cilium_enable_lb ? 1 : 0
  filename = "${path.module}/.gen/cilium-l2-policy.yaml"
  content = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata = {
      name = "l2-lb-policy"
    }
    spec = {
      loadBalancerIPs = true
      interfaces      = ["eth0"]
    }
  })
}

# Apply the CRs with kubectl (the Cilium CRDs do not expose a structural OpenAPI
# schema, which kubernetes_manifest cannot handle). Idempotent kubectl apply.
resource "terraform_data" "cilium_lb_apply" {
  count = var.cilium_enable_lb ? 1 : 0

  input = {
    kubeconfig = local_sensitive_file.kubeconfig.filename
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${local_sensitive_file.kubeconfig.filename} apply --server-side --force-conflicts -f ${local_file.cilium_lb_pool_yaml[0].filename} -f ${local_file.cilium_l2_policy_yaml[0].filename}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl --kubeconfig ${self.input.kubeconfig} delete --ignore-not-found -f ${path.module}/.gen/cilium-lb-pool.yaml -f ${path.module}/.gen/cilium-l2-policy.yaml || true"
  }

  depends_on = [terraform_data.cilium_lb_crd_ready]
}

# ---------------------------------------------------------------------------
# FASE 5: NFS storage (nfs-subdir-external-provisioner).
# Uses the existing NFS export 192.168.15.29:/NAS/kube_storage. A subdirectory
# is created on the NFS share per PVC; PVCs are read-write-once/many capable as
# long as the NFS client supports it. Installs a default StorageClass so plain
# PVCs (no storageClassName) are provisioned automatically.
# ---------------------------------------------------------------------------
module "storage" {
  source = "./modules/storage"

  nfs_server                = var.nfs_server
  nfs_path                  = var.nfs_path
  chart_version             = var.storage_chart_version
  storage_class_name        = var.storage_class_name
  set_default_storage_class = var.storage_set_default_class
  namespace                 = var.storage_namespace
  extra_values              = var.storage_extra_values

  depends_on = [module.cilium]
}

# ---------------------------------------------------------------------------
# FASE 4: Cluster API (Cluster API Operator + providers).
# Needed to later provision homogeneous workload clusters on the same Proxmox
# hypervisor via the CAPMOX infrastructure + in-cluster IPAM providers.
# ---------------------------------------------------------------------------
module "capi" {
  source = "./modules/capi"

  cert_manager_chart_version    = var.capi_cert_manager_chart_version
  operator_chart_version        = var.capi_operator_chart_version
  core_version                  = var.capi_core_version
  kubeadm_bootstrap_version     = var.capi_kubeadm_bootstrap_version
  kubeadm_control_plane_version = var.capi_kubeadm_control_plane_version
  proxmox_provider_version      = var.capi_proxmox_provider_version
  in_cluster_ipam_version       = var.capi_in_cluster_ipam_version

  provider_config_secret_name      = var.capi_config_secret_name
  provider_config_secret_namespace = var.capi_config_secret_namespace
  proxmox_url                      = var.capi_proxmox_url
  proxmox_token                    = var.capi_proxmox_token
  proxmox_secret                   = var.capi_proxmox_secret
  extra_values                     = var.capi_extra_values
  kubeconfig_path                  = local_sensitive_file.kubeconfig.filename

  depends_on = [module.storage]
}
