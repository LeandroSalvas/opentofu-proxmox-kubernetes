<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" alt="Licença: GPL-3.0">
  <img src="https://img.shields.io/badge/IaC-OpenTofu%20%E2%89%A51.7.0-orange.svg" alt="OpenTofu">
  <img src="https://img.shields.io/badge/Kubernetes-v1.36.3-326CE5.svg" alt="Kubernetes">
  <img src="https://img.shields.io/badge/OS-Talos%20Linux%20v1.13.0-purple.svg" alt="Talos Linux">
  <img src="https://img.shields.io/badge/CNI-Cilium%201.20.1-1793d1.svg" alt="Cilium">
  <img src="https://img.shields.io/badge/ClusterAPI-v1.12.11-brightgreen.svg" alt="Cluster API">
  <img src="https://img.shields.io/badge/Infrastructure%20Provider-CAPMOX%20v0.9.1-green.svg" alt="CAPMOX">
</p>

<p align="center">
  <strong>Kubernetes 100% reproduzível no Proxmox VE — SO imutável, rede eBPF e workers nascidos pelo próprio cluster.</strong>
</p>

---

> **🇺🇸 &nbsp;[Read this document in English (README.md)](README.md)**

---

# Kubernetes no Proxmox VE — OpenTofu · Talos · Cilium · Cluster API

Provisionamento de um cluster Kubernetes **altamente disponível (multi-master)** e de
nível "produção" em **Proxmox VE**, usando exclusivamente infraestrutura como código,
com uma aposta arquitetural central:

> **O sistema operacional é 100% imutável (sem SSH, sem gerenciador de pacotes), e o
> ciclo de vida dos nós worker é delegado ao próprio Kubernetes.**

Esta é uma implementação de nível homelab do padrão cloud-native de *inception*:
o OpenTofu constrói e sobe o plano de controle, e então o **Cluster API** assume a
responsabilidade de criar, escalar e destruir as VMs dos workers — declarativamente,
de dentro do cluster, sem nunca mais tocar no OpenTofu.

## Visão Geral e Arquitetura

O repositório implanta a stack completa de Kubernetes em **cinco fases compostáveis**,
cada uma mapeada para seu módulo OpenTofu. Toda fase passa por `tofu plan`/`tofu
apply`, então o ambiente inteiro é reproduzível — de um Proxmox VE vazio a um cluster
saudável, com storage e auto-scaling, em um único apply.
```
                         +--------------------------------------------+
                         |         Cluster Proxmox VE (2 nós)         |
                         |                                            |
    IaC (operador)       |   +------------------+  +---------------+  |
 +--------------------+  |   |   LB   HAProxy   |  |  Servidor NFS |  |
 | OpenTofu           |  |   |  192.168.15.113  |  |  192.168.15.29|  |
 |  + bpg/proxmox     |  |   |   :6443 -> CP    |  |  /NAS/kube_   |  |
 |  + siderolabs/talos|  |   +--------+---------+  |  storage      |  |
 |  + hashicorp/helm  |  |            |            +---------------+  |
 |  + kubernetes      |  |            v 6443                          |
 +--------------------+  |   +---------------------+                  |
        |                |   |  Plano de Controle  |                  |
        | API Talos      |   |  KuM1 .220 (etcd)   |                  |
        +--------------->|   |  KuM2 .221          |                  |
                         |   |  KuM3 .222          |                  |
                         |   +----------+----------+                  |
                         |              | rede de pods (Cilium)       |
                         |   +----------+----------+                  |
                         |   |  Workers (CAPI)     |                  |
                         |   |  KuW1 .225          |<-- IPPool        |
                         |   |  KuW2 .226          |   DHCP in-cluster|
                         |   +--------------------+                   |
                         +--------------------------------------------+
```

### As cinco fases

| Fase | O que é implantado | Artefato |
|------|--------------------|----------|
| **1 — Imagem e Compute** | Imagem Talos nocloud baixada/descomprimida por nó; VMs de control-plane e workers criadas com IPs estáticos | VMs prontas em modo maintenance |
| **2 — Bootstrap (Talos)** | Machine configs aplicadas (IP estático, hostname, disco de instalação), etcd bootstrapado, kubeconfig extraído | Cluster Talos saudável |
| **3 — CNI Cilium** | Datapath eBPF sem kube-proxy, com native routing; **cert SAN do kube-apiserver** corrigido para o IP do LB | Nós `Ready`, rede de pods |
| **4 — Cluster API** | Cluster API Operator + providers (core, kubeadm bootstrap/control-plane, **CAPMOX**, in-cluster IPAM) | Workers escaláveis de dentro do cluster |
| **5 — Storage NFS** | nfs-subdir-external-provisioner + `StorageClass` default `nfs-client` | Provisionamento dinâmico de PVCs |

### Decisões de design relevantes

- **Sem SSH.** O Talos expõe apenas uma API gRPC (`apid`, porta 50000). Provisionamento,
  upgrades e debug passam por `talosctl` / pelo provider Talos — nunca por acesso de
  shell. Isso elimina toda uma classe de vetores de erro humano (processos soltos,
  deriva de configuração, "funciona na minha máquina").
- **Endereçamento estático desde o primeiro boot.** O drive cloud-init (nocloud) do PVE
  entrega o IP estático antes de o sistema operacional rodar — nunca existe corrida de DHCP.
- **Descoberta de nós.** O provider Proxmox descobre dinamicamente os nós *online* e faz
  round-robin das VMs entre eles. O mesmo código OpenTofu roda inalterado em Proxmox de
  nó único ou multi-nó.
- **O LB é dependência dura do Cilium.** O Cilium roda com `k8sServiceHost=192.168.15.113`,
  portanto o frontend HAProxy `:6443` precisa estar ativo **antes** do apply do Cilium,
  ou os agentes não alcançam o API server e os nós nunca ficam `Ready`.
- **Inception / CAPI.** O plano de controle é provisionado por IaC; os workers são
  provisionados *pelo próprio cluster* via Cluster API + CAPMOX + in-cluster IPAM.
  Escalar = `kubectl apply` num `MachineDeployment`.
- **Identidade imutável.** Os segredos do cluster (CA + tokens) vivem no state do
  OpenTofu, então `plan`/`apply` são idempotentes — sem regeneração de segredos entre
  execuções.

## Stack Tecnológica

| Ferramenta | Papel na arquitetura |
|------------|----------------------|
| **OpenTofu** (≥ 1.7.0) | IaC declarativo dirigindo todas as fases; ciclo de vida único (`plan`/`apply`/`destroy`) para todo o ambiente |
| **Provider bpg/proxmox** | Provisionador node-aware: descoberta de nós online, download/descompressão da imagem Talos (import via SSH nos discos das VMs), criação de VMs com IP estático via nocloud |
| **Provider siderolabs/talos** | Geração/aplicação de machine configs, bootstrap do etcd, checks de saúde do cluster, extração de kubeconfig/talosconfig pela API gRPC do Talos |
| **Talos Linux v1.13.0** | SO 100% imutável (sem SSH, rootfs somente-leitura, tudo via API); hospeda Kubernetes v1.36.3 |
| **Cilium 1.20.1** | CNI com datapath eBPF, native routing (sem overlay/VXLAN), `kubeProxyReplacement` **sem kube-proxy**; masquerading e load balancing em BPF |
| **Cluster API Operator 0.29.0** | Instalação declarativa dos providers CAPI (core v1.12.11, kubeadm v1.12.11) |
| **CAPX — CAPMOX v0.9.1** | Provider de infraestrutura CAPI para Proxmox VE — cria/remove VMs de workers de dentro do cluster |
| **CABPT / CACPT (kubeadm v1.12.11)** | Providers bootstrap e control-plane do Cluster API que alimentam os workload clusters (KubeadmConfig / KubeadmControlPlane) |
| **in-cluster IPAM v1.1.0** | Alocação de endereços estilo DHCP in-cluster (`InClusterIPPool`) alimentando as máquinas do CAPMOX |
| **Provider Helm / cert-manager 1.21.1** | Deploy de Cilium, provisão NFS, cert-manager e do operator; o cert-manager assina os certificados de serving dos webhooks |
| **nfs-subdir-external-provisioner 4.0.18** | Provisionamento dinâmico da `StorageClass` default `nfs-client` sobre o servidor NFS do lab |

## Pré-requisitos

1. **OpenTofu ≥ 1.7.0** instalado na máquina que executa a IaC.
2. **Proxmox VE** (nó único ou cluster) com:
   - Um usuário para o provider, ex.: `terraform-prov@pve`, com direitos sobre VMs,
     storage e nós, além de **acesso SSH como root** (via agente) para o provider
     importar a imagem Talos (`pvesm path` + `qm disk import`).
   - Um **API token** para o Cluster API: `pveum user token add terraform-prov@pve capi --privsep 0`
     (o `ID` do token = `terraform-prov@pve!capi`; o `secret` retornado vai para o
     `terraform.tfvars`).
3. **Servidor NFS** exportando o diretório que sustentará a `StorageClass`
   (padrão: `192.168.15.29:/NAS/kube_storage`).
4. **HAProxy (ou qualquer LB)** encaminhando `TCP 6443` para os IPs do control-plane
   (veja `infra/lb/haproxy-k8s-api.cfg`). Necessário **antes** da fase Cilium.
5. **CLIs** (opcionais, mas recomendadas): `kubectl`, `talosctl`, `helm`.
6. Um agente SSH (`ssh-agent`) carregando a chave autorizada como `root` nos nós PVE.

## Como Usar

O projeto segue a abordagem **fail-fast e incremental**: cada fase é um `tofu apply`
separado, então se algo quebrar, o problema fica isolado naquela fase.

### Passo 1 — Clonar e configurar

```bash
git clone git@github.com:LeandroSalvas/opentofu-proxmox-kubernetes.git
cd opentofu-proxmox-kubernetes

cp terraform.tfvars.example terraform.tfvars
# preencha: proxmox_api_url, proxmox_user, proxmox_password,
#           capi_proxmox_url/token/secret, quantidades, recursos, ...
```

> **Segurança:** `terraform.tfvars` está no gitignore — nunca commite credenciais. Os
> valores `capi_proxmox_*` vêm do API token criado nos pré-requisitos.

### Passo 2 — Fundação e Bootstrap (Fases 1 e 2)

```bash
tofu init
tofu plan          # revise: download da imagem, VMs, bootstrap Talos
tofu apply
```

Durante o apply você verá, nesta ordem: download/descompressão da imagem em cada nó
Proxmox online → criação das VMs (IPs estáticos via cloud-init) → Talos em maintenance
→ aplicação das machine configs → bootstrap do etcd → checks de saúde do cluster.

Extraia as credenciais geradas:

```bash
# kubeconfig para kubectl/helm (já gravado pelo apply em ./kubeconfig.yaml, 0600)
tofu output -raw kubeconfig_raw > kubeconfig.yaml && chmod 600 kubeconfig.yaml

# talosconfig para o talosctl
tofu output -raw talos_config > talosconfig
chmod 600 talosconfig
export TALOSCONFIG="$PWD/talosconfig"
kubectl --kubeconfig kubeconfig.yaml get nodes
```

> Aqui os nós estarão `NotReady` **de propósito** — ainda não existe CNI.

### Passo 3 — Rede e Storage (Fases 3 e 5)

Garanta que o HAProxy encaminha `:6443` para o control-plane e então:

```bash
tofu plan
tofu apply        # instala Cilium (sem kube-proxy) + provisioner NFS
```

Conforme os agentes do Cilium sobem e o kube-proxy desaparece, cada nó transiciona
`NotReady → Ready`:

```bash
kubectl --kubeconfig kubeconfig.yaml get nodes -o wide   # todos Ready
```

> **Labels de role dos workers.** Ao final de cada apply, o resource
> `kubernetes_labels.worker` etiqueta cada máquina worker com
> `node-role.kubernetes.io/worker=""`, fazendo `kubectl get nodes` exibir `worker`
> na coluna ROLES e selectors como `node-role.kubernetes.io/worker=` casá-los.
> Aplicado in-cluster (sem alterar a machine config Talos), funciona para qualquer
> `worker_count`.

> **Serviços LoadBalancer (Fase 3b).** Com `cilium_enable_lb = true`, o apply
> também instala LB-IPAM + L2 Announcements do Cilium: um `CiliumLoadBalancerIPPool`
> é criado a partir de `cilium_lb_ipam_cidrs` (padrão `192.168.15.230-192.168.15.245`)
> e um `CiliumL2AnnouncementPolicy` anuncia esses IPs pela `eth0`. Qualquer Service
> com `type: LoadBalancer` passa a receber um IP real da LAN, sem MetalLB:
>
> ```bash
> kubectl apply -f examples/supermario.yaml          # demo: jogo HTTP atrás de um LB
> kubectl get svc supermario                         # EXTERNAL-IP, ex.: 192.168.15.230
> curl http://192.168.15.230/                        # funciona de qualquer cliente da LAN
> ```
>
> Mantenha o pool fora das faixas do DHCP/estáticas existentes. Defina
> `cilium_enable_lb = false` para desativar (cai para NodePort/port-forward).

Sanidade rápida do storage (provisionamento dinâmico via NFS):

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
# aguarde Bound, grave/leia um arquivo de um Pod, depois apague o PVC
```

### Passo 4 — Cluster API (Fase 4)

```bash
tofu plan
tofu apply        # cert-manager + operator + providers Core/Kubeadm/CAPMOX/IPAM
```

Valide os providers:

```bash
kubectl get coreproviders,bootstrapproviders,controlplaneproviders,infrastructureproviders,ipamproviders -A
```

#### Escalar workers sem tocar no OpenTofu

Como o ciclo de vida dos workers pertence ao Cluster API, adicionar capacidade é uma
operação **puramente Kubernetes**. Uma vez existindo um `ProxmoxCluster` + um
`MachineDeployment`/`ProxmoxMachineTemplate` de workers referenciando uma template VM
do CAPMOX, basta um `kubectl apply`:

```yaml
# exemplo/cluster.yaml (veja docs do CAPMOX para o spec completo)
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
kubectl --kubeconfig kubeconfig.yaml apply -f exemplo/cluster.yaml
kubectl get machines,machinedeployments -A     # os workers materializam e entram
```

> **Observação:** o provisionamento via CAPMOX exige uma **template VM** preparada no
> Proxmox e a configuração de `InClusterIPPool`/endereços do cluster. Este repositório
> instala e valida os providers (o contrato da IaC); o spec do workload cluster que você
> autora é específico de cada ambiente.

### Acessar o cluster a partir de outros hosts

As credenciais geradas vivem no state do OpenTofu (outputs `kubeconfig_raw` e
`talos_config`) e, após um apply, em disco como `./kubeconfig.yaml` (0600) — com
isso `kubectl` no host controlador funciona imediatamente. Para usar o cluster a
partir de outras máquinas, exporte essas configs com o helper do repositório,
que por padrão aponta o `server` da API para o load balancer HAProxy
(`https://192.168.15.113:6443` — o certificado do apiserver já tem um SAN para
esse endereço):

```bash
# pré-requisitos no host de destino: kubectl + rota TCP até 192.168.15.113:6443
scripts/export-kubeconfig.sh                                    # local -> ./kubeconfig.yaml
scripts/export-kubeconfig.sh --local                           # + instala em $HOME/.kube/config (com backup)
scripts/export-kubeconfig.sh --host voce@workstation            # + instala ~/.kube/config no remoto
scripts/export-kubeconfig.sh --talos --host voce@workstation    # + talosconfig para talosctl
```

Rodar o script **localmente** (sem `--host`/`--local`) grava a config em
`./kubeconfig.yaml` no repositório — **não** mexe em `~/.kube/config`. Para usar
`kubectl` na mesma máquina sem sobrescrever nada:

```bash
kubectl --kubeconfig ./kubeconfig.yaml get nodes               # não sobrescreve
scripts/export-kubeconfig.sh --local                           # ou instala em ~/.kube/config
```

O `--local` faz backup de um `$HOME/.kube/config` existente para
`$HOME/.kube/config.bak` antes de sobrescrever. Se preferir gravar direto, sem
backup (fundindo manualmente outros clusters que você tenha):

```bash
scripts/export-kubeconfig.sh --output ~/.kube/config
```

Equivalentes manuais, se preferir não usar o script:

```bash
scp kubeconfig.yaml voce@workstation:~/.kube/config && ssh voce@workstation chmod 600 ~/.kube/config
tofu output -raw kubeconfig_raw | ssh voce@workstation 'cat > ~/.kube/config && chmod 600 ~/.kube/config'
# apontar um kubeconfig existente para o LB em vez do primeiro control plane:
kubectl config set-cluster k8s-homelab --server=https://192.168.15.113:6443 --kubeconfig=~/.kube/config
# talosctl: tofu output -raw talos_config > talosconfig && chmod 600 talosconfig
```

> **Observação:** o `kubeconfig.yaml` e o `talosconfig` são removidos pelo
> `tofu destroy` — exporte-os *antes* de derrubar o cluster, ou regenere depois
> de um rebuild. Use `--endpoint <url>` para apontar o kubeconfig para qualquer
> outro endereço de apiserver alcançável, ou `--as-generated` para manter o
> endpoint do primeiro control plane que o Talos escreveu.

### Ferramentas visuais

O cluster já vem com um dashboard web e uma UI de terminal para a operação do
dia a dia. Ambas funcionam de qualquer host com rota de LAN para os nós.

- **Hubble UI** — service map de rede e dashboards de tráfego (DNS, drops, TCP,
  fluxos, status HTTP) alimentados pelo Hubble do Cilium, expostos como serviço
  `NodePort`: `http://<ip-de-qualquer-worker>:31235`. As variáveis
  `cilium_hubble_ui_enabled`, `cilium_hubble_ui_service_type` (`NodePort` /
  `LoadBalancer`) e `cilium_hubble_metrics_enabled` controlam o deploy do
  relay/UI/métricas.

- **k9s** — TUI prática para navegar em pods, deployments, logs e eventos usando
  o mesmo kubeconfig que o apply grava:

  ```bash
  k9s --kubeconfig ./kubeconfig.yaml          # ou KUBECONFIG=$PWD/kubeconfig.yaml
  ```

### Distribuição dinâmica das VMs por utilização

As VMs novas são distribuídas entre os nós online do Proxmox pela **utilização
atual dos hosts**, e não por um round-robin estático. No momento do plan cada
nó é pontuado pelo uso de CPU e memória ao vivo (`placement_cpu_weight` /
`placement_mem_weight`, ambos default `0.5`), os hosts são ordenados do menos
carregado para o mais carregado e as VMs são posicionadas sobre um anel
ponderado cujos slots são proporcionais à folga de cada host. IPs, IDs de VM e
o layout do cluster não mudam.

```bash
# ex.: priorizar memória livre sobre CPU livre na pontuação dos hosts:
tofu apply -var placement_mem_weight=0.7 -var placement_cpu_weight=0.3
```

> **Observação:** o posicionamento vale **apenas na criação**. As VMs existentes
> mantêm o nó Proxmox (`lifecycle.ignore_changes` no `node_name`), então variação
> de utilização nunca dispara migrações ao vivo — rebalancear um cluster em
> execução é feito manualmente (ex.: `qm migrate` ou recriação).


## Estrutura de Diretórios

```
opentofu-proxmox-kubernetes/
├── main.tf                 # descoberta de nós, pools de IP, wiring dos módulos, fases 1-5
├── providers.tf            # providers proxmox, helm, kubernetes (kubeconfig compartilhado)
├── variables.tf            # todos os ajustes: quantidades, IPs, recursos, versões, segredos
├── versions.tf             # constraints de versão do OpenTofu/providers
├── outputs.tf              # kubeconfig_raw, talos_config, mapas de nós, endpoints
├── terraform.tfvars.example# template de credenciais/IPs (terraform.tfvars está no gitignore)
├── infra/
│   └── lb/
│       └── haproxy-k8s-api.cfg   # HAProxy :6443 -> control plane (pré-requisito do LB)
├── modules/
│   ├── image/              # download + descompressão da imagem Talos em cada nó Proxmox online
│   ├── compute/            # VMs master/worker, IPs estáticos via cloud-init, round-robin
│   ├── bootstrap/          # machine configs Talos, bootstrap do etcd, kubeconfig/talosconfig
│   ├── cilium/             # Cilium eBPF, sem kube-proxy, native routing, patch de cert SAN
│   ├── storage/            # provisioner NFS subdir + StorageClass default nfs-client
│   └── capi/               # cert-manager + Cluster API Operator + providers CAPI
└── LICENSE                 # GPL-3.0
```

> **No gitignore, nunca commitados:** `terraform.tfvars`, `*.tfstate*`, `*.tfplan`,
> `kubeconfig.yaml`, `.terraform/`. O `talosconfig` e o `kubeconfig.yaml` são
> gerados/derivados pelo próprio apply.

## Valor Operacional

- **Velocidade:** um `apply` (ou quatro incrementais) constrói um cluster HA completo
  com CNI, storage e Cluster API — reproduzível em minutos, não em dias.
- **Reprodutibilidade:** SO imutável + IaC declarativa significam infraestrutura
  idêntica a cada vez; um teardown/rebuild completo resultou em `No changes`.
- **Menos erro humano:** sem SSH, sem deriva de configuração, sem joins manuais de nó
  — os dois passos mais propensos a erro (bootstrap e provisionamento de workers) são
  totalmente automatizados.
- **Escalabilidade self-service:** capacidade é um `kubectl apply`, não um ticket de infra.

## Contribuição e Licença

Correções e melhorias são bem-vindas — abra uma issue ou um PR. Este projeto é
distribuído sob a licença [GPL-3.0](LICENSE).
