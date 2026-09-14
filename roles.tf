import {
  to = okta_admin_role_custom.mcp_read_only
  id = "cr016sa0rvcfKrmbt698"
}

resource "okta_admin_role_custom" "mcp_read_only" {
  description = "Read-only view of users and groups for the identity MCP server. No write permissions by construction, managed with Terraform."
  label       = "Identity MCP Read-Only"
  permissions = ["okta.groups.read", "okta.users.userprofile.read"]
}