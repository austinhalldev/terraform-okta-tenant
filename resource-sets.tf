import {
  to = okta_resource_set.mcp_resources
  id = "iam16sa6uq6xrAUNi698"
}

resource "okta_resource_set" "mcp_resources" {
  label       = "Identity MCP Resources"
  description = "All users and all groups, read-only, for the identity MCP server."
  resources = [
    "${var.okta_org_url}/api/v1/users",
    "${var.okta_org_url}/api/v1/groups",
  ]
}