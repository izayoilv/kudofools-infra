# kudofools-infra

Kubernetes cluster infrastructure managed by Flux CD on a single-node k3s (Raspberry Pi 5, Debian 13, 8GB RAM).

## Architecture

```mermaid
flowchart TB
    DEV["Meshed devices<br/>laptop · phone"]

    subgraph EXT["External"]
        CF["Cloudflare<br/>DNS + Tunnel"]
        NB["NetBird server"]
        RH["rathole relay"]
    end

    subgraph CL["k3s — Raspberry Pi 5"]
        subgraph GITOPS["Continuous delivery"]
            REPO["Git repos"] --> FLUX["Flux CD"]
            TOFU["tofu-controller"]
        end

        subgraph SEC["Secrets"]
            OB["OpenBao"] --> ESO["External Secrets"]
        end

        TLS["cert-manager"]
        TR["Traefik ingress"]

        subgraph APPS["Applications"]
            FJ["Forgejo"]
            WP["Woodpecker CI + BuildKit"]
            ZOT["Zot registry"]
            LL["lldap"]
            MX["Conduit + Element"]
            VW["Vaultwarden"]
            RC["rathole client"]
        end

        subgraph OBS["Observability"]
            OTEL["OTel Collector"]
            LOKI[("Loki")]
            PROM[("Prometheus")]
            GRAF["Grafana"]
            AM["Alertmanager"]
            MAR["Matrix alerts bridge"]
        end
    end

    DEV -->|WireGuard mesh| NB
    CF -->|public| TR
    NB -->|mesh| TR
    RH -->|registry.kudofools.dev| RC

    REPO -->|reconcile| TOFU
    FLUX -.->|deploys| APPS
    FLUX -.->|deploys| OBS
    TOFU -->|tunnel + DNS| CF
    TOFU -->|configures| OB

    ESO -.->|injects| APPS
    ESO -.->|injects| OBS

    TLS -.->|certificates| TR
    TR --> APPS
    TR -->|mesh-only UI| SEC
    TR -->|mesh-only UI| OBS

    OTEL -->|logs| LOKI
    OTEL -->|metrics| PROM
    PROM -.->|scrapes| APPS
    PROM --> GRAF
    LOKI --> GRAF
    PROM -->|alerts| AM
    AM -->|webhook| MAR
    MAR -->|Matrix API| MX

    classDef actor fill:#fff4e5,stroke:#d68b00,color:#5c3d00
    classDef edge fill:#eef2f7,stroke:#7d8da1,color:#2f3b4a
    classDef gitops fill:#e8f0fe,stroke:#4a7ddb,color:#173a75
    classDef secret fill:#f3e8fd,stroke:#9b6dd6,color:#4b2680
    classDef platform fill:#e6f4ea,stroke:#3fa06b,color:#0f5132
    classDef app fill:#ffffff,stroke:#8a94a6,color:#2f3b4a
    classDef obs fill:#fdeaea,stroke:#d96c5f,color:#7a1f17
    classDef store fill:#fff8e1,stroke:#d8a800,color:#5c4300

    class DEV actor
    class CF,NB,RH edge
    class REPO,FLUX,TOFU gitops
    class OB,ESO secret
    class TLS,TR platform
    class FJ,WP,ZOT,LL,MX,VW,RC app
    class OTEL,GRAF,AM,MAR obs
    class LOKI,PROM store
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
├── kudofools-monitoring.yaml# Kustomization: syncs monitoring CRs (PodMonitor, alert rules)
├── intikepri-*.yaml         # intikepri-related Flux resources
├── infra/                   # Applied by infra
│   ├── system/              # Namespaces, LimitRanges, NetworkPolicies, PVCs
│   ├── platform/
│   │   ├── ingress/         # Traefik Ingress rules + middlewares
│   │   ├── eso/             # External Secrets HelmRelease
│   │   ├── tofu-controller/ # tofu-controller HelmRelease
│   │   ├── image-automation/# Flux image automation controllers
│   │   ├── monitoring/      # Prometheus, Loki, Grafana, OTel Collector, Matrix alerts
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
- [Matrix (Conduit) operations](./docs/matrix.md) — admin room, password recovery, alerts bot
- [OpenBao seeds guide](./docs/openbao.md) — secret paths, seed commands, rotation pointers
