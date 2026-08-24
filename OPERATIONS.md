# Operations

## OpenBao re-seal

After any pod restart (node reboot, OOM, etc.), OpenBao reseals:

```bash
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[0]' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[1]' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[2]' ~/.bao-keys.json)
```

OpenBao's container has `readOnlyRootFilesystem: true`, so `bao login` cannot persist the token. Pass the root token via `BAO_TOKEN` env var instead:

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao <command>
```


## Flux health

```bash
flux get kustomizations
flux get helmreleases -A
```

## Rotating secrets

All secrets are stored in OpenBao and synced by ESO. After updating OpenBao, force ESO to sync (see below).

All commands require the OpenBao root token:

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
```

### Rathole relay token (external access)

The rathole relay token must match between the in-cluster client (`kv/rathole/client.toml` → `client.toml`) and the relay server's `server.toml` on the VPS.

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)

# 1. Generate a new token and rebuild the client.toml (see SETUP.md step 7)
RATHOLE_TOKEN=$(openssl rand -base64 32)

# 2. Update OpenBao (recreate the client.toml entry with the new token)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/rathole/client.toml \
  client.toml="$(cat /tmp/rathole-client.toml)"

# 3. Force ESO sync
kubectl annotate externalsecret -n rathole rathole-client force-sync=$(date +%s) --overwrite

# 4. Update the VPS server.toml with the same token and restart the relay
```

The rathole client pod restarts when the mounted secret changes (or force it with `kubectl rollout restart deployment -n rathole rathole-client`).

### Woodpecker agent secret

```bash
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv patch kv/woodpecker/secrets WOODPECKER_AGENT_SECRET=<new-value>
```

### Forgejo secrets

```bash
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv patch kv/forgejo/secrets LFS_JWT_SECRET=<new-value>
```

## Regenerate Forgejo OAuth

Generate new credentials in Forgejo UI (Settings → Applications → OAuth2), then update OpenBao:

```bash
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv patch kv/woodpecker/secrets \
  WOODPECKER_FORGEJO_CLIENT=<new-client-id> \
  WOODPECKER_FORGEJO_SECRET=<new-client-secret>
```

## Force ESO sync

ESO refreshes secrets every 1h by default. Force an immediate sync per secret:

```bash
kubectl annotate externalsecret -n rathole rathole-client force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n lldap lldap-secrets force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n zot zot-ldap-creds force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n woodpecker woodpecker-secrets force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n forgejo forgejo-secrets force-sync=$(date +%s) --overwrite
```

## Webhook token

The Receiver triggers reconciliation on push, eliminating the need for frequent polling.

| GitRepository | Receiver | ExternalSecret | Token path |
|---|---|---|---|
| `flux-system` (kudofools-infra) | `kudofools-infra-webhook` | `kudofools-infra-webhook` | `kv/kudofools-infra/webhook-token` |
| `matrix-conduit` | `matrix-conduit-webhook` | `matrix-conduit-webhook` | `kv/matrix-conduit/webhook-token` |
| `element-web` | `element-web-webhook` | `element-web-webhook` | `kv/element-web/webhook-token` |

To set up:

```bash
# 1. Generate token
KUDOFOOLS_TOKEN=$(openssl rand -base64 32)

# 2. Set root token and write to OpenBao
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/kudofools-infra/webhook-token token=$KUDOFOOLS_TOKEN

# 3. Get webhook path
echo "kudofools-infra internal: http://webhook-receiver.flux-system.svc.cluster.local:80$(kubectl get receiver -n flux-system kudofools-infra-webhook -o jsonpath='{.status.webhookPath}')"
echo "kudofools-infra public:   https://flux-webhook.kudofools.dev$(kubectl get receiver -n flux-system kudofools-infra-webhook -o jsonpath='{.status.webhookPath}')"
```

### Forgejo webhook configuration

Go to **kudofools-infra repo → Settings → Webhooks → Add Webhook** and select **Forgejo**:

| Field | Value |
|---|---|
| Target URL | `http://webhook-receiver.flux-system.svc.cluster.local:80<webhook-path>` |
| HTTP Method | POST |
| POST Content Type | `application/json` |
| Secret | the token from `kv/kudofools-infra/webhook-token` |
| Trigger On | Push Events |
| Branch filter | `main` |

Flux validates via `X-Hub-Signature` HMAC (not the Authorization header).

### Matrix Conduit webhook setup

```bash
# 1. Generate token
CONDUIT_TOKEN=$(openssl rand -base64 32)

# 2. Write to OpenBao
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/matrix-conduit/webhook-token token=$CONDUIT_TOKEN

# 3. Force ESO sync
kubectl annotate externalsecret -n flux-system matrix-conduit-webhook force-sync=$(date +%s) --overwrite

# 4. Get webhook path
echo "matrix-conduit internal: http://webhook-receiver.flux-system.svc.cluster.local:80$(kubectl get receiver -n flux-system matrix-conduit-webhook -o jsonpath='{.status.webhookPath}')"
echo "matrix-conduit public:   https://flux-webhook.kudofools.dev$(kubectl get receiver -n flux-system matrix-conduit-webhook -o jsonpath='{.status.webhookPath}')"
```

Then configure the webhook in the **matrix-conduit repo → Settings → Webhooks → Add Webhook** (select **Forgejo**):

| Field | Value |
|---|---|
| Target URL | `http://webhook-receiver.flux-system.svc.cluster.local:80<webhook-path>` |
| HTTP Method | POST |
| POST Content Type | `application/json` |
| Secret | the token from `kv/matrix-conduit/webhook-token` |
| Trigger On | Push Events |
| Branch filter | `main` |

Flux validates via `X-Hub-Signature` HMAC (not the Authorization header).

### Element Web webhook setup

```bash
# 1. Generate token
ELEMENT_TOKEN=$(openssl rand -base64 32)

# 2. Write to OpenBao
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/element-web/webhook-token token=$ELEMENT_TOKEN

# 3. Force ESO sync
kubectl annotate externalsecret -n flux-system element-web-webhook force-sync=$(date +%s) --overwrite

# 4. Get webhook path
echo "element-web internal: http://webhook-receiver.flux-system.svc.cluster.local:80$(kubectl get receiver -n flux-system element-web-webhook -o jsonpath='{.status.webhookPath}')"
echo "element-web public:   https://flux-webhook.kudofools.dev$(kubectl get receiver -n flux-system element-web-webhook -o jsonpath='{.status.webhookPath}')"
```

Then configure the webhook in the **element-web repo → Settings → Webhooks → Add Webhook** (select **Forgejo**):

| Field | Value |
|---|---|
| Target URL | `http://webhook-receiver.flux-system.svc.cluster.local:80<webhook-path>` |
| HTTP Method | POST |
| POST Content Type | `application/json` |
| Secret | the token from `kv/element-web/webhook-token` |
| Trigger On | Push Events |
| Branch filter | `main` |

Flux validates via `X-Hub-Signature` HMAC (not the Authorization header).

### Force ESO sync

```bash
kubectl annotate externalsecret -n flux-system kudofools-infra-webhook force-sync=$(date +%s) --overwrite
```

## Image webhook (zot → Flux)

Image pushes to zot trigger instant image-automation scans: zot's `events` extension POSTs to a **generic** Flux Receiver on every push, which forces the ImageRepository to re-scan (instead of waiting up to 12h).

Generic receivers accept any POST; security is the random webhook path (no signature check, unlike the Forgejo webhooks).

Current wiring (in `clusters/default/infra/apps/zot/config.yaml` + `clusters/default/intikepri-static-image.yaml`):

| ImageRepository | Receiver | zot events sink |
|---|---|---|
| `intikepri-static` | `intikepri-static-image` (type `generic`) | one HTTP sink → receiver's internal webhook URL |

To add a new image webhook (e.g. after migrating another repo to zot):

```bash
# 1. Add a generic Receiver for the ImageRepository (kudofools-infra manifest):
#    type: generic, secretRef: <existing webhook secret>, resources: [ImageRepository/<name>]

# 2. Get the generated webhook path (after Flux applies the receiver)
echo "internal: http://webhook-receiver.flux-system.svc.cluster.local:80$(kubectl get receiver -n flux-system <receiver-name> -o jsonpath='{.status.webhookPath}')"

# 3. Add the address to zot's events sinks (clusters/default/infra/apps/zot/config.yaml)
#    and restart zot (ConfigMap is subPath-mounted):
kubectl rollout restart deployment -n zot zot
```

Note: one sink fires on **all** zot pushes, so a single receiver triggers scans for every repo — extra scans are harmless.

## Updating OpenTofu Configs

1. Edit files in `opentofu/`
2. Push to main branch
3. tofu-controller auto-detects changes and applies

To force immediate reconciliation instead of waiting for the interval:

```bash
kubectl annotate terraform -n flux-system opentofu reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
```

## Reconciling Image Automation Resources

To force immediate reconciliation of image automation resources instead of waiting for the polling interval:

```bash
# Force ImageRepository to check the zot registry
kubectl annotate imagerepository -n flux-system intikepri-static reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate imagerepository -n flux-system intikepri-cms reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux

# Force ImagePolicy to re-evaluate tag ordering
kubectl annotate imagepolicy -n flux-system intikepri-static reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate imagepolicy -n flux-system intikepri-cms reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux

# Force ImageUpdateAutomation to commit image updates
kubectl annotate imageupdateautomation -n flux-system intikepri-static reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate imageupdateautomation -n flux-system intikepri-cms reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux

# Force Receiver to process webhook
kubectl annotate receiver -n flux-system intikepri-static-git reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate receiver -n flux-system intikepri-static-image reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate receiver -n flux-system intikepri-cms-git reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate receiver -n flux-system intikepri-cms-image reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
kubectl annotate receiver -n flux-system kudofools-infra-webhook reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux
```

## Building the rathole client image

The arm64 `rathole-client` image is built by Woodpecker (`.woodpecker/rathole.yml`) from `rathole/Dockerfile` and pushed to the internal zot as `zot.zot.svc:5000/public/rathole-client:0.5.0`. The pipeline triggers only when `rathole/Dockerfile` or `.woodpecker/rathole.yml` change.

To bump the rathole version: change `RATHOLE_VERSION` in `rathole/Dockerfile`, the image tag in `.woodpecker/rathole.yml`, and the image reference in `clusters/default/infra/apps/rathole/deployment.yaml`.

## Drift Recovery

If tofu-controller reports drift:

```bash
kubectl get terraform -n flux-system opentofu -o yaml
kubectl describe terraform -n flux-system opentofu
```

## Security

### OpenBao exposed via internet

OpenBao UI is accessible at `openbao.kudofools.dev` through Cloudflare. Protections in place:

- **Authentication**: `userpass` auth with dedicated UI user (not root token)
- **Rate limiting**: Traefik middleware (100 req/10s via ipStrategy)
- **Security headers**: HSTS, XSS protection, nosniff, strict referrer policy
- **Audit log**: All API requests logged to `/tmp/audit.log` (checked via `kubectl exec -n openbao openbao-0 -- cat /tmp/audit.log`)
- **TLS**: Cloudflare edge terminates TLS; internal traffic is plaintext on cluster network

For additional protection, consider [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/) as an extra auth layer in front of the tunnel.

## Known issues

### `curlimages/curl` DNS resolution fails in-cluster

`curlimages/curl` images after v7.77 have DNS resolution problems in Kubernetes due to Alpine's musl libc resolver interacting badly with `ndots:5` and search domains in `/etc/resolv.conf`. The symptom is `curl: (6) Could not resolve host`.

Use `alpine:3.21` + `apk add curl` instead, or use `curlimages/curl:7.77.0`.
