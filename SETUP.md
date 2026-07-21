# Setup

## 1. Node configuration

**`/etc/rancher/k3s/registries.yaml`** — allows containerd to pull from the internal HTTP registry. The FQDN resolves via CoreDNS, which is available once the cluster is running:

```yaml
mirrors:
  "registry-service.registry.svc:5000":
    endpoint:
      - "http://registry-service.registry.svc:5000"
configs:
  "registry-service.registry.svc:5000":
    auth:
      username: admin
      password: <password>
    tls:
      insecure_skip_verify: true
```

Restart k3s: `sudo systemctl restart k3s`

## 2. Bootstrap Flux

```bash
curl -s https://fluxcd.io/install.sh | sudo bash
flux bootstrap git \
  --url=https://forgejo.kudofools.dev/izayoilv/kudofools-infra.git \
  --branch=main \
  --username=izayoilv \
  --password=<personal-access-token> \
  --token-auth \
  --path=./clusters/default
```

This creates `clusters/default/flux-system/`. After bootstrap, Flux syncs all Kustomizations automatically on push.

## 3. Apply everything

Push to main. Flux picks up all Kustomizations in `clusters/default/`.

## 4. Create OpenTofu bootstrap secret

The OpenTofu configs need Cloudflare and OpenBao credentials. Create this Secret before tofu-controller applies:

```bash
kubectl create secret generic -n flux-system opentofu-secrets \
  --from-literal=cloudflare_api_token='<token>' \
  --from-literal=openbao_token=$ROOT_TOKEN \
  --from-literal=cloudflare_zone_id='<zone-id>' \
  --from-literal=cloudflare_account_id='<account-id>'
```

These are bootstrap secrets — they can't come from OpenBao since OpenTofu is configuring OpenBao itself.

## 5. Bootstrap OpenBao

OpenBao is deployed by Flux but starts sealed. SSH into the node:

```bash
# Install CLI
curl -sL https://github.com/openbao/openbao/releases/download/v2.5.5/bao-hsm_2.5.5_Linux_arm64.tar.gz -o /tmp/bao.tar.gz
tar xzf /tmp/bao.tar.gz -C /tmp
sudo install /tmp/bao /usr/local/bin/bao

# Initialize (do this once)
kubectl exec -n openbao openbao-0 -- bao operator init -format=json > ~/.bao-keys.json

# SAFELY BACK UP ~/.bao-keys.json — root token and 5 unseal keys.
# Without it, OpenBao data is unrecoverable.

# Unseal (required after every pod restart)
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[0]' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[1]' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- bao operator unseal $(jq -r '.unseal_keys_hex[2]' ~/.bao-keys.json)
```

Note: `bao login` cannot persist the token file because OpenBao's container has `readOnlyRootFilesystem: true`. Use `BAO_TOKEN` env var for subsequent commands instead:

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao ...
```

## 6. Verify OpenTofu applied OpenBao config

The tofu-controller should auto-apply `opentofu/` configs (KV mount, policies, Kubernetes auth role).

```bash
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao secrets list
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao policy list
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao read auth/kubernetes/config
```

## 7. Seed secrets into OpenBao

All secrets are managed by OpenBao + ESO. No secrets are committed to Git.

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)

# woodpecker
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/woodpecker/secrets \
  WOODPECKER_AGENT_SECRET=<value> \
  WOODPECKER_FORGEJO_CLIENT=<value> \
  WOODPECKER_FORGEJO_SECRET=<value>"

# registry — generate htpasswd entry, store the raw bcrypt line
NEW_PASS=$(openssl rand -base64 32)
echo "Plain-text password (save for Woodpecker UI): $NEW_PASS"
HTPASSWD=$(htpasswd -Bbn admin "$NEW_PASS")
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/registry/auth \
  auth.htpasswd='$HTPASSWD'"

# forgejo
FORGEJO_POD=$(kubectl get pod -n forgejo -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].metadata.name}')

SECRETS=$(kubectl exec -n forgejo "$FORGEJO_POD" -- sh -c '
  echo "LFS_JWT_SECRET=$(forgejo generate secret LFS_JWT_SECRET)"
  echo "INTERNAL_TOKEN=$(forgejo generate secret INTERNAL_TOKEN)"
  echo "JWT_SECRET=$(forgejo generate secret JWT_SECRET)"
')

kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao kv put kv/forgejo/secrets \
  LFS_JWT_SECRET='$(echo "$SECRETS" | grep "^LFS_JWT_SECRET=" | cut -d= -f2)' \
  INTERNAL_TOKEN='$(echo "$SECRETS" | grep "^INTERNAL_TOKEN=" | cut -d= -f2)' \
  JWT_SECRET='$(echo "$SECRETS" | grep "^JWT_SECRET=" | cut -d= -f2)'"
```

## 8. Configure Web UI user

OpenTofu enables userpass auth and creates a ui-admin policy. Create your admin user with a generated password:

```bash
ROOT_TOKEN=$(jq -r '.root_token' ~/.bao-keys.json)

UI_PASS=$(openssl rand -base64 32)
kubectl exec -n openbao openbao-0 -- env BAO_TOKEN=$ROOT_TOKEN bao write auth/userpass/users/admin \
  password=$UI_PASS token_policies=ui-admin

echo "Web UI password: $UI_PASS"
```

Log in at https://openbao.kudofools.dev/ui/ with the password above. The username is `admin`.

## 9. Trigger ESO sync

Force ESO to sync immediately:

```bash
kubectl annotate externalsecret -n registry registry-auth force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n woodpecker woodpecker-secrets force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret -n forgejo forgejo-secrets force-sync=$(date +%s) --overwrite
```

Verify:

```bash
kubectl get externalsecrets -A
kubectl get secret -n registry registry-auth -o jsonpath='{.data.auth\.htpasswd}' | base64 -d
```

By default, ESO syncs every 1h (configured in `external-secrets.yaml`).

## 10. Woodpecker UI secret

Set in Woodpecker web UI (`https://woodpecker.kudofools.dev` → infra → Settings → Secrets):

| Name | Value |
|------|-------|
| `REGISTRY_PASSWORD` | Plain-text password used to generate the htpasswd entry in `kv/registry/auth` |

## 11. Forgejo OAuth app

Registered in Forgejo web UI (Settings → Applications → OAuth2 Applications):

- Redirect URI: `https://woodpecker.kudofools.dev/authorize`
- Client ID + Secret → stored in OpenBao `kv/woodpecker/secrets`

## 12. Forgejo config

The `forgejo-config` ConfigMap is managed by Flux from `clusters/default/infra/apps/forgejo/forgejo-config.yaml`. The 3 secrets (LFS_JWT_SECRET, INTERNAL_TOKEN, JWT_SECRET) are injected via ESO env vars — see step 7.

To update non-secret config, edit `forgejo-config.yaml`, push, and Flux syncs. Restart forgejo:

```bash
kubectl rollout restart deployment -n forgejo forgejo
```

## Pushing images to the internal registry

The registry at `registry-service.registry.svc:5000` is HTTP-only and not exposed externally.

### Via SSH tunnel (manual push from another device)

```bash
# Forward localhost:5000 to the in-cluster registry
ssh -L 5000:registry-service.registry.svc:5000 izayoilv@rpi5 -N

# Tag and push (docker trusts localhost without TLS)
docker tag alpine:latest localhost:5000/my-image:latest
docker push localhost:5000/my-image:latest
```

### Via Woodpecker CI (automated build and push)

Builds run in the `woodpecker-pipelines` namespace and push via buildkitd.

```yaml
steps:
  build-and-push:
    image: alpine:3.21
    environment:
      REGISTRY_PASSWORD:
        from_secret: registry_password
    commands:
      - apk add --no-cache curl
      - curl -sL https://github.com/moby/buildkit/releases/download/v0.31.0/buildkit-v0.31.0.linux-arm64.tar.gz | tar -xz -C /usr/local bin/buildctl
      - buildctl --addr tcp://buildkitd-service.buildkitd.svc:1234 build \
          --frontend dockerfile.v0 \
          --local context=/tmp/build \
          --local dockerfile=/tmp/build \
          --output type=image,name=registry-service.registry.svc:5000/my-image:latest,push=true,registry.insecure=true,registry.username=admin,registry.password=$REGISTRY_PASSWORD
```

To verify the push succeeded, query the registry API from the pipeline:

```yaml
  verify:
    image: alpine:3.21
    environment:
      REGISTRY_PASSWORD:
        from_secret: registry_password
    commands:
      - apk add --no-cache curl
      - STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:$REGISTRY_PASSWORD" "http://registry-service.registry.svc:5000/v2/my-image/manifests/latest" -H "Accept: application/vnd.oci.image.manifest.v1+json")
      - test "$STATUS" = "200" && echo "Image verified"
```

## CI/CD flow

Push to main → Flux syncs manifests to the cluster.

(No CI pipelines for this repo — builds happen in external projects via Woodpecker.)

## Adding a new service

1. Create `clusters/default/infra/apps/{name}/` with `kustomization.yaml`
2. Add the directory to `clusters/default/infra/kustomization.yaml`
3. Push
