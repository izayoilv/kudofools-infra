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
      - hostname: flux-webhook.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: conduit.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: element.kudofools.dev
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: lldap.kudofools.dev
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

resource "cloudflare_dns_record" "flux_webhook_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "flux-webhook"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "conduit_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "conduit"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "element_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "element"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "turn_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "turn"
  type    = "A"
  content = "45.32.109.191"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "registry_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "registry"
  type    = "A"
  content = "45.32.109.191"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "lldap_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "lldap"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.kudofools.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "openbao_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "openbao"
  type    = "A"
  content = "45.32.109.191"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "netbird_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "netbird"
  type    = "A"
  content = "45.32.109.191"
  proxied = false
  ttl     = 1
}

resource "cloudflare_dns_record" "dashboard_netbird_dev" {
  zone_id = var.cloudflare_zone_id
  name    = "dashboard.netbird"
  type    = "A"
  content = "45.32.109.191"
  proxied = false
  ttl     = 1
}

resource "random_id" "waterstop_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "waterstop" {
  provider      = cloudflare.waterstop
  account_id    = var.waterstop_cloudflare_account_id
  name          = "waterstop-tunnel"
  tunnel_secret = random_id.waterstop_tunnel_secret.b64_std
}

locals {
  waterstop_credentials_json = jsonencode({
    AccountTag   = var.waterstop_cloudflare_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.waterstop.id
    TunnelSecret = random_id.waterstop_tunnel_secret.b64_std
    TunnelName   = "waterstop-tunnel"
  })

  waterstop_config_yaml = <<-EOF
    tunnel: ${cloudflare_zero_trust_tunnel_cloudflared.waterstop.id}
    credentials-file: /etc/cloudflared/credentials.json
    transport-loglevel: warn
    ingress:
      - hostname: waterstop.id
        service: http://traefik.kube-system.svc.cluster.local:80
      - hostname: www.waterstop.id
        service: http://traefik.kube-system.svc.cluster.local:80
      - service: http_status:404
  EOF
}

resource "kubernetes_secret_v1" "waterstop_cloudflared_credentials" {
  metadata {
    name      = "waterstop-cloudflared-credentials"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"       = "waterstop-cloudflared"
      "app.kubernetes.io/part-of"    = "waterstop"
      "app.kubernetes.io/managed-by" = "flux"
    }
  }
  type = "Opaque"
  data = {
    "credentials.json" = local.waterstop_credentials_json
  }
}

resource "kubernetes_config_map_v1" "waterstop_cloudflared_config" {
  metadata {
    name      = "waterstop-cloudflared-config"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"       = "waterstop-cloudflared"
      "app.kubernetes.io/part-of"    = "waterstop"
      "app.kubernetes.io/managed-by" = "flux"
    }
  }
  data = {
    "config.yaml" = local.waterstop_config_yaml
  }
}

resource "cloudflare_dns_record" "waterstop_apex" {
  provider = cloudflare.waterstop
  zone_id  = var.waterstop_cloudflare_zone_id
  name     = "@"
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.waterstop.id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}

resource "cloudflare_dns_record" "waterstop_www" {
  provider = cloudflare.waterstop
  zone_id  = var.waterstop_cloudflare_zone_id
  name     = "www"
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.waterstop.id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}

resource "cloudflare_ruleset" "waterstop_www_redirect" {
  provider    = cloudflare.waterstop
  zone_id     = var.waterstop_cloudflare_zone_id
  name        = "redirect-www-to-apex"
  description = "Permanent redirect www.waterstop.id to waterstop.id"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    description = "Redirect www to apex"
    expression  = "(http.host eq \"www.waterstop.id\")"
    action      = "redirect"
    enabled     = true
    action_parameters = {
      from_value = {
        status_code           = 301
        preserve_query_string = true
        target_url = {
          expression = "concat(\"https://waterstop.id\", http.request.uri.path)"
        }
      }
    }
  }]
}
