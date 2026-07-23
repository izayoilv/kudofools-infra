resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "kudofools" {
  account_id    = var.cloudflare_account_id
  name          = "tunnel"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

locals {
  credentials_json = jsonencode({
    AccountTag   = var.cloudflare_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.kudofools.id
    TunnelSecret = random_id.tunnel_secret.b64_std
    TunnelName   = "tunnel"
  })

  config_yaml = <<-EOF
    tunnel: ${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}
    credentials-file: /etc/cloudflared/credentials.json
    transport-loglevel: warn
    ingress:
      - hostname: forgejo.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: woodpecker.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: openbao.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: flux-webhook.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - service: http_status:404
  EOF
}

resource "kubernetes_secret_v1" "cloudflared_credentials" {
  metadata {
    name      = "cloudflared-credentials"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"       = "cloudflared"
      "app.kubernetes.io/part-of"    = "kudofools"
      "app.kubernetes.io/managed-by" = "flux"
    }
  }
  type = "Opaque"
  data = {
    "credentials.json" = local.credentials_json
  }
}

resource "kubernetes_config_map_v1" "cloudflared_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"       = "cloudflared"
      "app.kubernetes.io/part-of"    = "kudofools"
      "app.kubernetes.io/managed-by" = "flux"
    }
  }
  data = {
    "config.yaml" = local.config_yaml
  }
}

resource "cloudflare_dns_record" "forgejo_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "forgejo"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "woodpecker_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "woodpecker"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "openbao_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "openbao"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "flux_webhook_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "flux-webhook"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
