resource "okta_app_oauth_role_assignment" "mcp_binding" {
  client_id    = var.mcp_client_id
  type         = "CUSTOM"
  role         = okta_admin_role_custom.mcp_read_only.id
  resource_set = okta_resource_set.mcp_resources.id
}