# ---------------------------------------------------------------------------
# FASE 6: Kubernetes Dashboard (official web UI).
#
# Official helm chart (kubernetes-dashboard v7, last release of the archived
# upstream project). It runs five components behind a DBless Kong gateway:
# api, auth, web, kong and metrics-scraper. External traffic hits the
# `kubernetes-dashboard-kong-proxy` service (HTTPS 443); exposing it via
# NodePort keeps the URL predictable and independent of the Cilium LB pool.
# The bundled metrics-server subchart feeds the CPU/memory charts and
# `kubectl top` (works on Talos with --kubelet-insecure-tls / InternalIP).
#
# Login needs a bearer token: `kubectl -n <namespace> create token
# dashboard-admin --duration=24h`. The ServiceAccount + ClusterRoleBinding
# below give that token cluster-admin access.
# ---------------------------------------------------------------------------

locals {
  dashboard_values = yamlencode(merge({
    kong = {
      proxy = {
        type = var.service_type
        tls = {
          nodePort = var.node_port
        }
        http = {
          enabled = false
        }
      }
    }
    metrics-server = {
      enabled = var.metrics_server_enabled
    }
  }))
}

resource "helm_release" "kubernetes_dashboard" {
  name             = "kubernetes-dashboard"
  repository       = "https://kubernetes-retired.github.io/dashboard/"
  chart            = "kubernetes-dashboard"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true

  values = concat([local.dashboard_values], var.extra_values)

  timeout = 600
}

# ServiceAccount whose short-lived tokens unlock the dashboard's admin views.
resource "kubernetes_service_account_v1" "dashboard_admin" {
  metadata {
    name      = "dashboard-admin"
    namespace = var.namespace
  }

  depends_on = [helm_release.kubernetes_dashboard]
}

resource "kubernetes_cluster_role_binding_v1" "dashboard_admin" {
  metadata {
    name = "kubernetes-dashboard-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.dashboard_admin.metadata[0].name
    namespace = var.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  depends_on = [kubernetes_service_account_v1.dashboard_admin]
}