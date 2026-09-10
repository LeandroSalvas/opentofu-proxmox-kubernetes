<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="License: GPL-3.0">
  <img src="https://img.shields.io/badge/IaC-OpenTofu%20%E2%89%A51.7.0-orange.svg" alt="OpenTofu">
  <img src="https://img.shields.io/badge/Kubernetes-v1.36.3-326CE5.svg" alt="Kubernetes">
  <img src="https://img.shields.io/badge/OS-Talos%20Linux%20v1.13.0-purple.svg" alt="Talos Linux">
  <img src="https://img.shields.io/badge/CNI-Cilium%201.20.1-1793d1.svg" alt="Cilium">
  <img src="https://img.shields.io/badge/ClusterAPI-v1.12.11-brightgreen.svg" alt="Cluster API">
  <img src="https://img.shields.io/badge/Infrastructure%20Provider-CAPMOX%20v0.9.1-green.svg" alt="CAPMOX">
</p>

<p align="center">
  <strong>100% reproducible Kubernetes on Proxmox VE — immutable OS, eBPF networking, and workers born directly from the cluster itself.</strong>
</p>

---

> **🇧🇷 &nbsp;[Leia este documento em português (README.pt-BR.md)](README.pt-BR.md)**

---

# Kubernetes on Proxmox VE — OpenTofu · Talos · Cilium · Cluster API

Provisioning a highly available (multi-master), production-grade Kubernetes cluster on
**Proxmox VE** using pure infrastructure-as-code, with one bold architectural bet:

> **The operating system is 100% immutable (no SSH, no package manager), and the
> lifecycle of the worker nodes is delegated to Kubernetes itself.**

This is a homelab-grade implementation of a cloud-native "inception" pattern:
OpenTofu builds and boots the management/control plane, and then **Cluster API**
takes over the responsibility of creating, scaling, and destroying worker VMs —
declaratively, from inside the cluster, without ever touching OpenTofu again.

## Overview and Architecture

The repository deploys a complete Kubernetes stack in **five composable phases**,
each mapped to its own OpenTofu module. Every phase runs through `tofu plan`/`tofu
apply`, so the whole environment is reproducible from an empty Proxmox VE to a
healthy, storage-backed, self-scaling cluster in a single apply.

```
                         +--------------------------------------------+
                         |         Proxmox VE cluster (2 nodes)       |
                         |                                            |
    IaC (operator)       |   +------------------+  +---------------+  |
 +--------------------+  |   |   LB  HAProxy    |  |   NFS Server  |  |
 | OpenTofu           |  |   |  192.168.15.113  |  |  192.168.15.29|  |
 |  + bpg/proxmox     |  |   |   :6443 -> CP    |  |  /NAS/kube_   |  |
 |  + siderolabs/talos|  |   +--------+---------+  |  storage      |  |
 |  + hashicorp/helm  |  |            |            +---------------+  |
 |  + kubernetes      |  |            v 6443                          |
 +--------------------+  |   +---------------------+                  |
        |                |   |  Control Plane      |                  |
        | Talos API      |   |  KuM1 .220 (etcd)   |                  |
        +--------------->|   |  KuM2 .221          |                  |
                         |   |  KuM3 .222          |                  |
                         |   +----------+----------+                  |
                         |              | pod network (Cilium)        |
                         |   +----------+----------+                  |
                         |   |  Workers (CAPI)     |                  |
                         |   |  KuW1 .225          |<-- IPPool        |
                         |   |  KuW2 .226          |   DHCP in-cluster|
                         |   +--------------------+                   |
                         +--------------------------------------------+
```

### The five phases

| Phase | What is deployed | Artifact |
|-------|------------------|----------|
| **1 — Image & Compute** | Talos nocloud image downloaded/decompressed per node; control-plane + worker VMs created with static IPs | VMs ready in maintenance mode |
| **2 — Bootstrap (Talos)** | Machine configs applied (static IP, hostname, install disk), etcd bootstrapped, kubeconfig extracted | Healthy Talos cluster |
| **3 — Cilium CNI** | kube-proxy-free eBPF datapath with native routing; **kube-apiserver cert SAN** patched for the LB address | Nodes `Ready`, pod networking |
| **4 — Cluster API** | Cluster API Operator + providers (core, kubeadm bootstrap/control-plane, **CAPMOX**, in-cluster IPAM) | Workers scalable from inside the cluster |
| **5 — NFS Storage** | nfs-subdir-external-provisioner + default `StorageClass` `nfs-client` | Dynamic PVC provisioning |

### Design decisions worth knowing

- **No SSH.** Talos exposes only a gRPC API (`apid`, port 50000). Provisioning, upgrades
  and debugging go through `talosctl` / the Talos provider — never through shell access.
  This removes an entire class of human-error vectors (stray processes, config drift,
  "it worked on my machine").
- **Static addressing from the very first boot.** The PVE cloud-init (nocloud) drive
  delivers the static IP before the OS runs, so there is never a DHCP race.
- **Node-aware discovery.** The Proxmox provider discovers *online* nodes dynamically
  and round-robins the VMs across them. The same OpenTofu code runs on a single-node
  or multi-node Proxmox cluster unchanged.
- **The LB is a hard dependency of Cilium.** Cilium runs with
  `k8sServiceHost=192.168.15.113`, so the HAProxy `:6443` frontend must be active
  *before* the Cilium apply, or the agents cannot reach the API server and nodes never
  become `Ready`.
- **Inception / CAPI.** The control plane is provisioned by IaC; the workers are
  provisioned *by the cluster itself* via Cluster API + CAPMOX + in-cluster IPAM.
  Scaling up = `kubectl apply` on a `MachineDeployment`.
- **Immutable identity.** Cluster secrets (CA + tokens) live in the OpenTofu state,
  so `plan`/`apply` are idempotent — no secret regeneration between runs.

## Technology Stack

| Tool | Role in the architecture |
|------|--------------------------|
| **OpenTofu** (≥ 1.7.0) | Declarative IaC driving every phase; single lifecycle (`plan`/`apply`/`destroy`) for the whole environment |
| **bpg/proxmox provider** | Node-aware provisioner: online-node discovery, Talos image download/decompression (SSH-import into VM disks), VM creation with nocloud static IPs |
| **siderolabs/talos provider** | Machine-config generation/applies, etcd bootstrap, cluster health checks, kubeconfig/talosconfig extraction over the Talos gRPC API |
| **Talos Linux v1.13.0** | 100% immutable OS (no SSH, read-only rootfs, API-driven); hosts Kubernetes v1.36.3 |
| **Cilium 1.20.1** | CNI with eBPF datapath, native routing (no overlay/VXLAN), `kubeProxyReplacement` **without kube-proxy**; masquerading and load balancing in BPF |
| **Cluster API Operator 0.29.0** | Declarative installation of the CAPI providers (core v1.12.11, kubeadm v1.12.11) |
| **CAPX — CAPMOX v0.9.1** | CAPI infrastructure provider for Proxmox VE — creates/removes worker VMs from inside the cluster |
| **CABPT / CACPT (kubeadm v1.12.11)** | Cluster API bootstrap + control-plane providers that power the workload clusters (KubeadmConfig / KubeadmControlPlane) |
| **in-cluster IPAM v1.1.0** | In-cluster DHCP-like address allocation (`InClusterIPPool`) feeding CAPMOX machines |
| **Helm provider / cert-manager 1.21.1** | Deploys Cilium, NFS provisioner, cert-manager and the operator; cert-manager signs the webhook serving certs |
| **nfs-subdir-external-provisioner 4.0.18** | Dynamic provisioning of the default `StorageClass` `nfs-client` backed by the lab NFS server |

## Prerequisites

1. **OpenTofu ≥ 1.7.0** installed on the machine that runs the IaC.
2. **Proxmox VE** (single node or cluster) with:
   - A user for the provider, e.g. `terraform-prov@pve`, with rights over VMs, storage
     and nodes, plus **SSH access as root** (via an agent) so the provider can import
     the Talos image (`pvesm path` + `qm disk import`).
   - An **API token** for Cluster API: `pveum user token add terraform-prov@pve capi --privsep 0`
     (the token `ID` = `terraform-prov@pve!capi` and the returned `secret` go into
     `terraform.tfvars`).
3. **NFS server** exporting the directory that will back the `StorageClass`
   (default: `192.168.15.29:/NAS/kube_storage`).
4. **HAProxy (or any LB)** that forwards `TCP 6443` to the control-plane IPs
   (see `infra/lb/haproxy-k8s-api.cfg`). Required **before** the Cilium phase.
5. **CLIs** (optional but recommended): `kubectl`, `talosctl`, `helm`.
6. An SSH agent (`ssh-agent`) carrying the key authorized as `root` on the PVE nodes.

## How To Use

The project follows a **fail-fast, incremental** approach: each phase is a separate
`tofu apply`, so if something breaks you isolated the problem to that phase.

### Step 1 — Clone and configure

```bash
git clone git@github.com:LeandroSalvas/opentofu-proxmox-kubernetes.git
cd opentofu-proxmox-kubernetes

cp terraform.tfvars.example terraform.tfvars
# fill in: proxmox_api_url, proxmox_user, proxmox_password,
#          capi_proxmox_url/token/secret, counts, resources, ...
```

> **Security:** `terraform.tfvars` is gitignored — never commit credentials. The
> `capi_proxmox_*` values come from the API token created in the prerequisites.

### Step 2 — Foundation & Bootstrap (Phases 1 & 2)

```bash
tofu init
tofu plan          # review: image download, VMs, Talos bootstrap
tofu apply
```

During the apply you will see, in order: image download/decompression on every online
Proxmox node → VM creation (static IPs from the cloud-init drive) → Talos maintenance
→ machine-config apply → etcd bootstrap → cluster health checks.

Extract the generated credentials:

```bash
# kubeconfig for kubectl/helm (already written by the apply to ./kubeconfig.yaml, 0600)
tofu output -raw kubeconfig_raw > kubeconfig.yaml && chmod 600 kubeconfig.yaml

# talosconfig for talosctl
tofu output -raw talos_config > talosconfig
chmod 600 talosconfig
export TALOSCONFIG="$PWD/talosconfig"
kubectl --kubeconfig kubeconfig.yaml get nodes
```

> The nodes will be `NotReady` at this point **by design** — there is no CNI yet.

### Step 3 — Networking & Storage (Phases 3 & 5)

Ensure HAProxy forwards `:6443` to the control plane, then:

```bash
tofu plan
tofu apply        # installs Cilium (kube-proxy-free) + NFS provisioner
```

As Cilium agents come up and kube-proxy is gone, every node transitions
`NotReady → Ready`:

```bash
kubectl --kubeconfig kubeconfig.yaml get nodes -o wide   # all Ready
```

> **Worker role labels.** At the end of every apply, the `kubernetes_labels.worker`
> resource tags each worker machine with `node-role.kubernetes.io/worker=""`, so
> `kubectl get nodes` shows `worker` under ROLES and selectors like
> `node-role.kubernetes.io/worker=` match them. This is applied in-cluster (no
> Talos machine-config change), so it works for any `worker_count`.

> **LoadBalancer services (Phase 3b).** With `cilium_enable_lb = true` the apply
> also installs Cilium LB-IPAM + L2 Announcements: a `CiliumLoadBalancerIPPool`
> is created from `cilium_lb_ipam_cidrs` (default `192.168.15.230-192.168.15.245`)
> and a `CiliumL2AnnouncementPolicy` announces those IPs over `eth0`. Any Service
> with `type: LoadBalancer` then gets a real LAN IP with no MetalLB:
>
> ```bash
> kubectl apply -f examples/supermario.yaml          # demo: HTTP game behind a LB
> kubectl get svc supermario                         # EXTERNAL-IP, e.g. 192.168.15.230
> curl http://192.168.15.230/                        # works from any LAN client
> ```
>
> Keep the pool out of your DHCP/existing static ranges. Set
> `cilium_enable_lb = false` to disable (falls back to NodePort/port-forward).

Quick storage sanity check (dynamic provisioning over NFS):

```bash
kubectl --kubeconfig kubeconfig.yaml get storageclass        # nfs-client (default)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: smoke-test
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
# wait for Bound, write/read a file from a Pod, then delete the PVC
```

### Step 4 — Cluster API (Phase 4)

```bash
tofu plan
tofu apply        # cert-manager + operator + Core/Kubeadm/CAPMOX/IPAM providers
```

Validate the providers:

```bash
kubectl --kubeconfig kubeconfig.yaml get coreproviders,bootstrapproviders,controlplaneproviders,infrastructureproviders,ipamproviders -A
```

All five should settle with `INSTALLEDVERSION` set and `READY=True`:
`cluster-api` (core), `kubeadm` (bootstrap), `kubeadm` (control-plane),
`proxmox` (CAPMOX), `in-cluster` (IPAM).

#### Scaling workers without touching OpenTofu

Because the worker lifecycle belongs to Cluster API, adding capacity is a **pure
Kubernetes** operation. Once a `ProxmoxCluster` + a worker
`MachineDeployment`/`ProxmoxMachineTemplate` referencing a CAPMOX template VM exist,
`kubectl apply` is all you need:

```yaml
# example/cluster.yaml (see CAPMOX docs for the full spec)
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: capi-worker-lab
  namespace: default
spec:
  clusterNetwork:
    pods:      {cidrBlocks: ["10.245.0.0/16"]}
    services:  {cidrBlocks: ["10.96.0.0/12"]}
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha2
    kind: ProxmoxCluster
    name: capi-worker-lab
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: capi-worker-lab-md-0
  namespace: default
spec:
  clusterName: capi-worker-lab
  replicas: 3
  template:
    spec:
      clusterName: capi-worker-lab
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: capi-worker-lab-md-0
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1alpha2
        kind: ProxmoxMachineTemplate
        name: capi-worker-lab-md-0
```

```bash
kubectl --kubeconfig kubeconfig.yaml apply -f example/cluster.yaml
kubectl get machines,machinedeployments -A     # workers materialize & join
```

> **Note:** CAPMOX provisioning requires a prepared Proxmox **template VM** and the
> cluster's `InClusterIPPool`/address config. This repository installs and validates
> the providers (the IaC contract); the workload-cluster spec you author is
> environment-specific.

### Accessing the cluster from other hosts

The generated credentials live in OpenTofu's state (the `kubeconfig_raw` and
`talos_config` outputs) and, after an apply, on disk as `./kubeconfig.yaml`
(0600) — so `kubectl` on the controller host works immediately. To use the
cluster from other machines, export those configs with the bundled helper,
which by default points the API `server` at the HAProxy load balancer
(`https://192.168.15.113:6443` — the apiserver certificate already has a SAN for
that address):

```bash
# prerequisites on the target host: kubectl + TCP route to 192.168.15.113:6443
scripts/export-kubeconfig.sh                                    # local -> ./kubeconfig.yaml
scripts/export-kubeconfig.sh --local                           # + install into $HOME/.kube/config (with backup)
scripts/export-kubeconfig.sh --host you@workstation            # + install ~/.kube/config remotely
scripts/export-kubeconfig.sh --talos --host you@workstation    # + talosconfig for talosctl
```

Running the script **locally** (without `--host`/`--local`) writes the config to
`./kubeconfig.yaml` in the repo — it does **not** touch `~/.kube/config`. To use
`kubectl` on the same machine without overwriting anything:

```bash
kubectl --kubeconfig ./kubeconfig.yaml get nodes               # no overwrite
scripts/export-kubeconfig.sh --local                           # or install to ~/.kube/config
```

`--local` backs up an existing `$HOME/.kube/config` to
`$HOME/.kube/config.bak` before overwriting it. If you prefer to write directly
without a backup (merging any other clusters manually):

```bash
scripts/export-kubeconfig.sh --output ~/.kube/config
```

Manual equivalents, if you prefer not to use the script:

```bash
scp kubeconfig.yaml you@workstation:~/.kube/config && ssh you@workstation chmod 600 ~/.kube/config
tofu output -raw kubeconfig_raw | ssh you@workstation 'cat > ~/.kube/config && chmod 600 ~/.kube/config'
# point an existing kubeconfig at the load balancer instead of the first control plane:
kubectl config set-cluster k8s-homelab --server=https://192.168.15.113:6443 --kubeconfig=~/.kube/config
# talosctl: tofu output -raw talos_config > talosconfig && chmod 600 talosconfig
```

> **Note:** `kubeconfig.yaml` and `talosconfig` are removed by `tofu destroy` —
> export them *before* tearing the cluster down, or re-generate after a rebuild.
> Use `--endpoint <url>` to point the kubeconfig at any other reachable
> apiserver address, or `--as-generated` to keep the first control-plane
> endpoint Talos wrote.

### Visual tooling

The cluster ships with a web dashboard and a terminal UI for day‑to‑day
operation. Both are reachable from any host with a LAN route to the nodes.

- **Kubernetes Dashboard** — the official web UI (v7), served through its Kong
  gateway as a `NodePort` service (HTTPS): `https://<any-worker-ip>:30443`
  (e.g. `https://192.168.15.225:30443`). Accept the self-signed certificate.
  Login with a bearer token minted from the module's admin ServiceAccount:

  ```bash
  kubectl -n kubernetes-dashboard create token dashboard-admin --duration=24h
  ```

  The bundled metrics-server feeds the CPU/memory charts and `kubectl top`.
  `dashboard_service_type` / `dashboard_node_port` change how it's exposed
  (`ClusterIP`, `NodePort`, or `LoadBalancer` via the Cilium IP pool).

- **k9s** — handy TUI for navigating pods, deployments, logs and events against
  the same kubeconfig the apply writes:

  ```bash
  k9s --kubeconfig ./kubeconfig.yaml          # or KUBECONFIG=$PWD/kubeconfig.yaml
  ```

### Dynamic, load-aware VM placement

New VMs are spread across the online Proxmox nodes by **current host
utilization**, not by a static round-robin. At plan time each node is scored
from its live CPU and memory usage (`placement_cpu_weight` /
`placement_mem_weight`, both default `0.5`), the hosts are ordered
least-loaded first, and VMs are placed over a weighted ring whose slots are
proportional to each host's free headroom. IPs, VM IDs, and the cluster layout
are unchanged.

```bash
# e.g., prioritize free memory over free CPU when scoring hosts:
tofu apply -var placement_mem_weight=0.7 -var placement_cpu_weight=0.3
```

> **Note:** placement is applied **at creation time only**. Existing VMs keep
> their Proxmox node (`lifecycle.ignore_changes` on `node_name`), so utilization
> drift never triggers live migrations — rebalancing a running cluster is done
> manually (e.g., `qm migrate` or a recreate).


## Directory Structure

```
opentofu-proxmox-kubernetes/
├── main.tf                 # node discovery, IP pools, module wiring, phases 1-5
├── providers.tf            # proxmox, helm, kubernetes providers (shared kubeconfig)
├── variables.tf            # every tunable: counts, IPs, resources, versions, secrets
├── versions.tf             # provider/OpenTofu version constraints
├── outputs.tf              # kubeconfig_raw, talos_config, node maps, endpoints
├── terraform.tfvars.example# template for credentials/IPs (terraform.tfvars is gitignored)
├── infra/
│   └── lb/
│       └── haproxy-k8s-api.cfg   # HAProxy :6443 -> control plane (LB pre-requisite)
├── modules/
│   ├── image/              # download + decompress Talos image per online Proxmox node
│   ├── compute/            # master/worker VMs, static IPs via cloud-init, round-robin
│   ├── bootstrap/          # Talos machine configs, etcd bootstrap, kubeconfig/talosconfig
│   ├── cilium/             # eBPF Cilium, kube-proxy-free, native routing, cert SAN patch
│   ├── storage/            # NFS subdir provisioner + default StorageClass nfs-client
│   └── capi/               # cert-manager + Cluster API Operator + CAPI providers
└── LICENSE                 # GPL-3.0
```

> **Gitignored and never committed:** `terraform.tfvars`, `*.tfstate*`, `*.tfplan`,
> `kubeconfig.yaml`, `.terraform/`. The `talosconfig` and `kubeconfig.yaml` are
> regenerated/derived by the apply itself.

## Operational Value

- **Speed:** one `apply` (or four incremental ones) builds a full HA cluster with
  CNI, storage and Cluster API — repeatable in minutes, not days.
- **Reproducibility:** immutable OS + declarative IaC means identical infrastructure
  every time; a full teardown/rebuild produced `No changes`.
- **Reduced human error:** no SSH, no config drift, no manual node joins — the two
  most error-prone steps (bootstrap and worker provisioning) are fully automated.
- **Self-service scaling:** capacity is a `kubectl apply`, not an infra ticket.

## Contributing & License

Fixes and improvements are welcome — open an issue or a PR. This project is released
under the [GPL-3.0](LICENSE) license.
