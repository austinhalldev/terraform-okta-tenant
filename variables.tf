variable "okta_org_url" {
  description = "Base URL of the Okta tenant, e.g. https://example.okta.com"
  type        = string
}
variable "mcp_client_id" {
  description = "Client ID of the svc-okta-identity-mcp service app"
  type        = string
}