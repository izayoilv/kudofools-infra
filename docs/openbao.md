# OpenBao seeds guide

Every cluster secret lives in **OpenBao** (Vault-compatible) and reaches workloads through External Secrets Operator (ESO). Manifests are GitOps-managed; **seeds are manual** — nothing sensitive is ever committed.

Related: [SETUP.md](../SETUP.md) (bootstrap, OpenBao init/unseal), [OPERATIONS.md](../OPERATIONS.md) (rotation), [docs/matrix.md](./matrix.md).

## How it works

- KV v2 engine mounted at `kv/`; secrets are stored at `kv/<app>/<name>`.
- Policies refer to the API path with `data/`: `kv/data/<app>/*` (defined in `opentofu/openbao.tf`).
- ESO `ClusterSecretStore/openbao` → `http://openbao.openbao.svc:8200`, Kubernetes auth role `eso`, bound to ServiceAccount `external-secrets` in `flux-system`.
- Each app has a read policy added to the `eso` role. ExternalSecrets refresh every 1h (`refreshInterval: 1h`) and use `deletionPolicy: Retain`.

## Accessing the CLI

OpenBao's container has a read-only root filesystem, so `bao login` cannot persist a token. Use `BAO_TOKEN` instead:

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)

bao() { kubectl exec -n openbao openbao-0 -- env BAO_TOKEN="$ROOT_TOKEN" bao "$@"; }
```

After an OpenBao pod restart, unseal first (see OPERATIONS.md → OpenBao re-seal).

## Commands

| Action | Command |
|---|---|
| Create/overwrite a secret | `bao kv put kv/<app>/<name> KEY=value [KEY2=value2]` |
| Add/update one key | `bao kv patch kv/<app>/<name> KEY=value` |
| Read one key | `bao kv get -field=<key> kv/<app>/<name>` |
| List paths | `bao kv list kv/` or `bao kv list kv/<app>` |
| Delete a secret | `bao kv metadata delete kv/<app>/<name>` |

> `bao kv put` replaces the whole secret. Use `bao kv patch` to change one key without losing the others (e.g. rotating a single token).

Force ESO to sync immediately instead of waiting up to 1h:

```bash
kubectl annotate externalsecret -n <namespace> <name> force-sync=$(date +%s) --overwrite
kubectl get externalsecrets -A          # verify SECRETSYNCED=True
```

## Current seed paths

All paths are in the `kudofools` OpenBao instance unless noted.

| Path | Keys | Consumed by |
|---|---|---|
| `kv/woodpecker/secrets` | `WOODPECKER_AGENT_SECRET`, `WOODPECKER_FORGEJO_CLIENT`, `WOODPECKER_FORGEJO_SECRET` | Woodpecker server + agent |
| `kv/forgejo/secrets` | `LFS_JWT_SECRET`, `INTERNAL_TOKEN`, `JWT_SECRET` | Forgejo |
| `kv/lldap/secrets` | `LLDAP_LDAP_USER_PASS`, `LLDAP_JWT_SECRET`, `LLDAP_KEY_SEED` | lldap |
| `kv/zot/secrets` | `ldap-creds.json` | zot LDAP bind |
| `kv/zot/intikepri-image-creds` | `username`, `password` | Flux image automation (intikepri) |
| `kv/rathole/client.toml` | `client.toml` | rathole relay client |
| `kv/kudofools-infra/cloudflare-token` | `token` | cert-manager DNS-01 |
| `kv/kudofools-infra/netbird-mgmt-api-key` | `token` | NetBird operator |
| `kv/kudofools-infra/webhook-token` | `token` | Flux Receiver (this repo) |
| `kv/matrix-conduit/secrets` | `registration_token`, `TURN_SECRET` | Conduit |
| `kv/matrix-conduit/webhook-token` | `token` | Flux Receiver (matrix-conduit) |
| `kv/element-web/webhook-token` | `token` | Flux Receiver (element-web) |
| `kv/vaultwarden/admin-token` | `admin-token` | Vaultwarden admin panel |
| `kv/vaultwarden/webhook-token` | `token` | Flux Receiver (vaultwarden) |
| `kv/grafana/secrets` | `admin-user`, `admin-password` | Grafana (monitoring stack) |
| `kv/matrix-alertmanager-receiver/secrets` | `MATRIX_ACCESS_TOKEN` | Alertmanager → Matrix bridge |

Full per-app seed commands for the original bootstrap are in [SETUP.md §7](../SETUP.md). Monitoring seeds:

```bash
# Grafana admin login (save the generated password)
bao kv put kv/grafana/secrets \
  admin-user=admin \
  admin-password="$(openssl rand -base64 32)"

# Matrix bot access token — see docs/matrix.md for creating the @alerts bot
bao kv put kv/matrix-alertmanager-receiver/secrets \
  MATRIX_ACCESS_TOKEN='<bot access token>'
```

## Notes

- **intikepri** workloads use a separate OpenBao instance (`ClusterSecretStore/intikepri-openbao`); its seeds are documented in the `intikepri-infra` repo, not here.
- **Legacy:** `kv/registry/auth` (htpasswd for the pre-zot registry) is only referenced by old SETUP.md text — no manifest consumes it. Safe to leave or delete.
- Secret values generated for you (admin tokens, passwords) are shown once; store them in your password manager.
- Rotations: use `kv patch` + force-sync + a workload restart where the app reads secrets only at boot. See OPERATIONS.md.
