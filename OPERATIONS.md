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

### Registry password

The htpasswd entry in OpenBao and Woodpecker's `REGISTRY_PASSWORD` must stay in sync.

```bash
NEW_PASS=$(openssl rand -base64 32)
echo "Plain-text password (update in Woodpecker UI): $NEW_PASS"

HTPASSWD=$(htpasswd -Bbn admin "$NEW_PASS")
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv patch kv/registry/auth auth.htpasswd="$HTPASSWD"
```

The registry reads the htpasswd file on every request — no restart needed. Verify auth works:

```bash
kubectl run auth-check --image=alpine:3.21 --rm -it --restart=Never -n woodpecker-pipelines -- sh -c "
  apk add --no-cache curl
  curl -s -u 'admin:$NEW_PASS' 'http://registry-service.registry.svc:5000/v2/_catalog'
"
```

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
kubectl annotate externalsecret -n registry registry-auth force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n woodpecker woodpecker-secrets force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n forgejo forgejo-secrets force-sync=$(date +%s) --overwrite
```

Verify the Kubernetes secret was updated:

```bash
kubectl get secret -n registry registry-auth -o jsonpath='{.data.auth\.htpasswd}' | base64 -d
```

## Webhook token

The Receiver triggers reconciliation on push, eliminating the need for frequent polling.

| GitRepository | Receiver | ExternalSecret | Token path |
|---|---|---|---|
| `flux-system` (kudofools-infra) | `kudofools-infra-webhook` | `kudofools-infra-webhook` | `kv/kudofools-infra/webhook-token` |

To set up:

```bash
# 1. Generate token
KUDOFOOLS_TOKEN=$(openssl rand -base64 32)

# 2. Set root token and write to OpenBao
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/kudofools-infra/webhook-token token=$KUDOFOOLS_TOKEN

# 3. Get webhook path
echo "kudofools-infra internal: http://notification-controller.flux-system.svc.cluster.local:80$(kubectl get receiver -n flux-system kudofools-infra-webhook -o jsonpath='{.status.webhookPath}')"
echo "kudofools-infra public:   https://flux-webhook.kudofools.dev$(kubectl get receiver -n flux-system kudofools-infra-webhook -o jsonpath='{.status.webhookPath}')"
```

### Forgejo webhook configuration

Go to **kudofools-infra repo → Settings → Webhooks → Add Webhook** and select **Forgejo**:

| Field | Value |
|---|---|
| Target URL | `http://notification-controller.flux-system.svc.cluster.local:80<webhook-path>` |
| HTTP Method | POST |
| POST Content Type | `application/json` |
| Secret | the token from `kv/kudofools-infra/webhook-token` |
| Trigger On | Push Events |
| Branch filter | `main` |

Flux validates via `X-Hub-Signature` HMAC (not the Authorization header).

### Force ESO sync

```bash
kubectl annotate externalsecret -n flux-system kudofools-infra-webhook force-sync=$(date +%s) --overwrite
```

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
# Force ImageRepository to check Docker Hub
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
