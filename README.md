# kudofools-infra

Kubernetes cluster infrastructure managed by Flux CD on a single-node k3s (Raspberry Pi 5, Ubuntu 24.04, 8GB RAM).

## Architecture

```mermaid
graph LR
    %% External Network
    subgraph Ext [External]
        direction TB
        REPO[This Git Repo]
        CF[Cloudflare Tunnel]
    end

    %% K3s Cluster Boundary
    subgraph Cluster [K3s / Raspberry Pi Cluster]
        direction LR

        %% Core GitOps Logic
        subgraph GitOps [Continuous Delivery]
            FLUX[Flux CD]
            K8S_Res[(K8s Resources)]
        end

        %% Infrastructure-as-Code
        subgraph IaC [OpenTofu]
            TF[tofu-controller]
        end

        %% Security / Secret Syncing
        subgraph Security [Secret Engine]
            direction TB
            OB[OpenBao Store] -->|Fetch| ESO[External Secrets]
            ESO -->|Sync| K8S_Sec[(K8s Secrets)]
        end

        %% Routing Layer
        TR[Traefik Ingress]

        %% Target Applications Group
        subgraph Apps [Applications]
            direction LR
            FJ[Forgejo]
            WP[Woodpecker CI]
            REG[Registry]
            BK[BuildKit]
        end
    end

    %% --- CONNECTIONS ---

    %% GitOps Automation Paths
    REPO -->|Reconcile| FLUX
    FLUX --> K8S_Res
    FLUX -->|Deploy| OB

    %% OpenTofu manages cloudflared + OpenBao config
    REPO -->|Reconcile| TF
    TF -->|Creates Tunnel + DNS| CF
    TF -->|Configures| OB

    %% Network Routing Paths
    CF --> TR
    TR --> Apps

    %% Secret Consumptions
    K8S_Sec -.->|Inject| Apps
    K8S_Sec -.->|Auth| OB
```

## Prerequisites

- Device with k3s installed
- Domain with DNS pointing to the node (via Cloudflare Tunnel)
- Forgejo + Woodpecker already running

## Repo structure

```
clusters/default/
├── flux-system/             # Flux bootstrap (auto-generated)
├── kudofools-infra.yaml     # Kustomization: syncs infra/
├── kudofools-eso.yaml       # Kustomization: syncs eso-resources/
├── kudofools-opentofu.yaml  # Kustomization: syncs opentofu/ Terraform CRD
├── intikepri-*.yaml         # intikepri-related Flux resources
├── infra/                   # Applied by infra
│   ├── system/              # Namespaces, LimitRanges, NetworkPolicies, PVCs
│   ├── platform/
│   │   ├── ingress/         # Traefik Ingress rules + middlewares
│   │   ├── eso/             # External Secrets HelmRelease
│   │   ├── tofu-controller/ # tofu-controller HelmRelease
│   │   ├── image-automation/# Flux image automation controllers
│   │   └── cloudflared/     # Cloudflare Tunnel deployment (config managed by OpenTofu)
│   └── apps/
│       ├── openbao/         # Secrets engine (Vault-compatible)
│       ├── forgejo/         # Git server + CI webhooks
│       ├── lldap/           # LDAP directory (registry + app auth)
│       ├── zot/             # OCI registry (LDAP auth, per-repo ACLs)
│       ├── rathole/         # Reverse-proxy relay client (exposes services via VPS)
│       └── woodpecker/      # CI server + agent + buildkitd
├── platform/
│   └── eso-resources/       # ClusterSecretStore + ExternalSecrets
└── opentofu/                # Terraform CRD for OpenTofu
opentofu/                    # OpenTofu IaC (applied by tofu-controller)
    ├── main.tf              # Provider configs
    ├── cloudflare.tf        # Tunnel, credentials Secret, DNS records
    ├── openbao.tf           # OpenBao mounts, policies, auth config
    └── variables.tf         # Input variables
```

## Docs

- [Setup guide](./SETUP.md) — full setup steps
- [Operations](./OPERATIONS.md) — maintenance tasks
