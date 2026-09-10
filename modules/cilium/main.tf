# ---------------------------------------------------------------------------
# FASE 3: Cilium CNI on Talos, kube-proxy-free.
#
# Talos-specific requirements (from the official Talos docs):
#   * ipam.mode = kubernetes (Talos kube-controller-manager allocates podCIDRs)
#   * cgroup.autoMount.enabled = false, cgroup.hostRoot = /sys/fs/cgroup
#     (Talos already provides cgroupv2 and bpffs mounts)
#   * SYS_MODULE capability dropped (Talos forbids workload loading modules)
#   * kubeProxyReplacement = true + k8sServiceHost/Port (kube-proxy-free)
#
# The underlying cluster/kubernetes state is kube-proxy-free because the
# machine config disables Talos kube-proxy (cluster.proxy.disabled = true).
# ---------------------------------------------------------------------------
locals {
  platform_values = yamlencode(merge({
    ipam = {
      mode = "kubernetes"
    }
    kubeProxyReplacement  = true
    k8sServiceHost        = var.k8s_service_host
    k8sServicePort        = var.k8s_service_port
    routingMode           = "native"
    ipv4NativeRoutingCIDR = "10.244.0.0/16"
    autoDirectNodeRoutes  = true
    bpf = {
      masquerade = true
    }
    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN",
          "KILL",
          "NET_ADMIN",
          "NET_RAW",
          "IPC_LOCK",
          "SYS_ADMIN",
          "SYS_RESOURCE",
          "DAC_OVERRIDE",
          "FOWNER",
          "SETGID",
          "SETUID",
        ]
        cleanCiliumState = [
          "NET_ADMIN",
          "SYS_ADMIN",
          "SYS_RESOURCE",
        ]
      }
    }
    cgroup = {
      autoMount = {
        enabled = false
      }
      hostRoot = "/sys/fs/cgroup"
    }
    # Run on control plane nodes (taint) too.
    tolerations = [
      {
        key      = var.control_plane_taint
        operator = "Exists"
        effect   = "NoSchedule"
      },
      {
        operator = "Exists"
      },
    ]
    operator = {
      tolerations = [
        {
          key      = var.control_plane_taint
          operator = "Exists"
          effect   = "NoSchedule"
        },
        {
          operator = "Exists"
        },
      ]
    }
    # LoadBalancer services: Cilium LB-IPAM allocates an external IP from the
    # pool below and L2 announcements advertise it over the LAN (ARP). Requires
    # kube-proxy replacement (already enabled above). Explicit false == the
    # chart default, so disabling via cilium_enable_lb is a clean no-op.
    "enable-lb-ipam" = var.enable_lb
    l2announcements = {
      enabled = var.enable_lb
    }
    # Hubble: observe the cluster via a network service map / dashboards.
    # Agents already run with hubble.enabled=true; relay + UI live as their own
    # Deployments, and metrics make the UI dashboards meaningful.
    hubble = {
      relay = {
        enabled = var.hubble_ui_enabled
      }
      ui = {
        enabled = var.hubble_ui_enabled
        service = {
          type     = var.hubble_ui_service_type
          nodePort = var.hubble_ui_node_port
        }
      }
      metrics = {
        # null disables metrics entirely (avoid emitting `enabled: null`).
        enabled = var.hubble_metrics_enabled ? [
          "dns",
          "drop",
          "tcp",
          "flow",
          "icmp",
          "http",
        ] : null
      }
    }
  }))
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.chart_version
  namespace  = var.namespace

  values = concat([local.platform_values], var.extra_values)

  timeout = 600
}