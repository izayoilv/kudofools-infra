variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS and Tunnel permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for kudofools.dev"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "openbao_addr" {
  description = "OpenBao server address"
  type        = string
  default     = "http://openbao.openbao.svc:8200"
}

variable "openbao_token" {
  description = "OpenBao root token"
  type        = string
  sensitive   = true
}

variable "waterstop_cloudflare_api_token" {
  description = "Cloudflare API token for the waterstop.id account (tunnel + DNS + redirects)"
  type        = string
  sensitive   = true
}

variable "waterstop_cloudflare_account_id" {
  description = "Cloudflare account ID for waterstop.id"
  type        = string
}

variable "waterstop_cloudflare_zone_id" {
  description = "Cloudflare zone ID for waterstop.id"
  type        = string
}
