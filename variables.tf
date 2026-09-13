variable "okta_org_url" {
  description = "Base URL of the Okta tenant, e.g. https://example.okta.com"
  type        = string
}
variable "mcp_client_id" {
  description = "Client ID of the svc-okta-identity-mcp service app"
  type        = string
}
variable "mcp_jwks_kid" {
  description = "Key ID of the public key registered on the MCP service app"
  type        = string
}

variable "mcp_jwks_n" {
  description = "RSA modulus of the public key registered on the MCP service app"
  type        = string
}

variable "mcp_auth_policy_id" {
  description = "Authentication policy ID applied to the MCP service app"
  type        = string
}