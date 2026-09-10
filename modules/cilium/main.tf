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
  platform_values = yamlencode({
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
  })
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