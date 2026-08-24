resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc"
}

resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv-v2"
  description = "KV v2 secrets engine for kudofools"
}

resource "vault_policy" "woodpecker" {
  name   = "woodpecker"
  policy = <<EOT
path "kv/data/woodpecker/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "forgejo" {
  name   = "forgejo"
  policy = <<EOT
path "kv/data/forgejo/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "registry" {
  name   = "registry"
  policy = <<EOT
path "kv/data/registry/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_kubernetes_auth_backend_role" "eso" {
  backend                          = vault_kubernetes_auth_backend_config.kubernetes.backend
  role_name                        = "eso"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["flux-system"]
  token_policies                   = [vault_policy.woodpecker.name, vault_policy.forgejo.name, vault_policy.registry.name, vault_policy.kudofools_infra.name, vault_policy.matrix_conduit.name, vault_policy.element_web.name, vault_policy.lldap.name, vault_policy.zot.name, vault_policy.rathole.name]
  token_ttl                        = 3600
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

resource "vault_policy" "kudofools_infra" {
  name   = "kudofools-infra"
  policy = <<EOT
path "kv/data/kudofools-infra/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "matrix_conduit" {
  name   = "matrix-conduit"
  policy = <<EOT
path "kv/data/matrix-conduit/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "element_web" {
  name   = "element-web"
  policy = <<EOT
path "kv/data/element-web/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "lldap" {
  name   = "lldap"
  policy = <<EOT
path "kv/data/lldap/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "zot" {
  name   = "zot"
  policy = <<EOT
path "kv/data/zot/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "rathole" {
  name   = "rathole"
  policy = <<EOT
path "kv/data/rathole/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "ui_admin" {
  name   = "ui-admin"
  policy = <<EOT
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOT
}
