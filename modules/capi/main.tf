# ---------------------------------------------------------------------------
# FASE 4: Cluster API via the Cluster API Operator.
#
# The Operator (a controller-manager + CRDs installed by its own Helm chart)
# installs and manages the CAPI providers declaratively: the chart renders
# Provider CRs (CoreProvider, BootstrapProvider, ControlPlaneProvider,
# InfrastructureProvider, IPAMProvider) from `values`, and the Operator runs
# clusterctl internally against a config Secret we provide.
#
# Provider namespaces MUST match the namespaces the clusterctl components
# manifests expect (otherwise component ownership/labels break):
#   core          cluster-api -> capi-system
#   bootstrap     kubeadm      -> capi-kubeadm-bootstrap-system
#   controlPlane  kubeadm      -> capi-kubeadm-control-plane-system
#   infrastructure proxmox      -> capmox-system
#   ipam          in-cluster   -> capi-ipam-in-cluster-system
# ---------------------------------------------------------------------------

# cert-manager: hard prerequisite. Both the Operator webhook and every provider
# webhook inject their serving CA via cert-manager
# (cert-manager.io/inject-ca-from), so it must be installed and healthy first.
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version
  namespace  = "cert-manager"
  create_namespace = true

  values = [yamlencode({
    installCRDs = true
  })]
}

# The CAPMOX provider expects to live in capmox-system. Create the namespace
# explicitly (instead of letting the chart do it via createNamespace) so the
# config Secret below has a deterministic home and no ownership conflicts.
resource "kubernetes_namespace_v1" "capmox_system" {
  metadata {
    name = "capmox-system"
  }

  depends_on = [helm_release.cert_manager]
}

# config Secret consumed by the Operator to fill clusterctl variables while
# installing the providers (initReaderVariables). The CAPMOX components.yaml
# template substitutes ${PROXMOX_URL=""}/${PROXMOX_TOKEN=""}/${PROXMOX_SECRET=""}
# from these keys to build the capmox-manager-credentials Secret.
resource "kubernetes_secret_v1" "capmox_credentials" {
  metadata {
    name      = var.provider_config_secret_name
    namespace = var.provider_config_secret_namespace
  }

  data = {
    PROXMOX_URL    = var.proxmox_url
    PROXMOX_TOKEN  = var.proxmox_token
    PROXMOX_SECRET = var.proxmox_secret
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.capmox_system]
}

locals {
  capi_values = yamlencode({
    core = {
      cluster-api = {
        version   = var.core_version
        namespace = "capi-system"
      }
    }
    bootstrap = {
      kubeadm = {
        version   = var.kubeadm_bootstrap_version
        namespace = "capi-kubeadm-bootstrap-system"
      }
    }
    controlPlane = {
      kubeadm = {
        version   = var.kubeadm_control_plane_version
        namespace = "capi-kubeadm-control-plane-system"
      }
    }
    infrastructure = {
      proxmox = {
        version          = var.proxmox_provider_version
        namespace        = "capmox-system"
        createNamespace  = false
      }
    }
    ipam = {
      in-cluster = {
        version   = var.in_cluster_ipam_version
        namespace = "capi-ipam-in-cluster-system"
      }
    }
    configSecret = {
      name      = var.provider_config_secret_name
      namespace = var.provider_config_secret_namespace
    }
  })
}

resource "helm_release" "cluster_api_operator" {
  name       = "cluster-api-operator"
  repository = "https://kubernetes-sigs.github.io/cluster-api-operator"
  chart      = "cluster-api-operator"
  version    = var.operator_chart_version
  namespace  = "capi-operator-system"
  create_namespace = true

  values = concat([local.capi_values], var.extra_values)

  # cert-manager CRDs must exist before the Operator can use them for its
  # service accounts/webhook certificates; the config Secret must exist before
  # the provider request is reconciled.
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.capmox_credentials]

  timeout = 600
}

# ---------------------------------------------------------------------------
# Cleanup on destroy: the cluster-api-operator chart renders the Provider CRs
# (CoreProvider, BootstrapProvider, ...) from `values`. Those CRs carry a
# finalizer `provider.cluster.x-k8s.io` that only the Operator controller can
# remove. When the Operator is uninstalled together with those CRs, the
# controller is gone before it can finalize them, leaving the CRs stuck in
# Terminating and blocking the kubernetes_namespace_v1.capmox_system destroy.
#
# This resource depends on the Operator release, so on destroy Terraform runs
# it BEFORE the Helm uninstall (reverse dependency order): the Operator is still
# running and can resolve the finalizers cleanly. If any CR still lingers, we
# force-remove its finalizer and delete the now-orphaned provider namespaces.
# ---------------------------------------------------------------------------
resource "terraform_data" "capi_provider_cleanup" {
  # Capture the kubeconfig location in the resource itself: destroy-time
  # provisioners may only reference `self`, so the path is kept in `input`.
  # `triggers_replace` also re-runs it if the path changes across applies.
  input = var.kubeconfig_path

  depends_on = [helm_release.cluster_api_operator]

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      KUBECONFIG="${self.input}" kubectl delete coreprovider cluster-api \
        -n capi-system --ignore-not-found --wait=false || true
      KUBECONFIG="${self.input}" kubectl delete bootstrapprovider kubeadm \
        -n capi-kubeadm-bootstrap-system --ignore-not-found --wait=false || true
      KUBECONFIG="${self.input}" kubectl delete controlplaneprovider kubeadm \
        -n capi-kubeadm-control-plane-system --ignore-not-found --wait=false || true
      KUBECONFIG="${self.input}" kubectl delete infrastructureprovider proxmox \
        -n capmox-system --ignore-not-found --wait=false || true
      KUBECONFIG="${self.input}" kubectl delete ipamprovider in-cluster \
        -n capi-ipam-in-cluster-system --ignore-not-found --wait=false || true
      sleep 10
      for cr in \
        "coreprovider cluster-api capi-system" \
        "bootstrapprovider kubeadm capi-kubeadm-bootstrap-system" \
        "controlplaneprovider kubeadm capi-kubeadm-control-plane-system" \
        "infrastructureprovider proxmox capmox-system" \
        "ipamprovider in-cluster capi-ipam-in-cluster-system"; do
        set -- $cr
        KUBECONFIG="${self.input}" kubectl patch "$1" "$2" -n "$3" --ignore-not-found \
          --type merge -p '{"metadata":{"finalizers":[]}}' || true
      done
      KUBECONFIG="${self.input}" kubectl delete namespace \
        capi-system capi-kubeadm-bootstrap-system capi-kubeadm-control-plane-system \
        capmox-system capi-ipam-in-cluster-system capi-operator-system \
        --ignore-not-found --wait=false || true
    EOT
  }
}