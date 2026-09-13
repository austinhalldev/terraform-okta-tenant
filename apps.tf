import {
  to = okta_app_oauth.mcp_server
  id = var.mcp_client_id

}
resource "okta_app_oauth" "mcp_server" {
  accessibility_error_redirect_url = null
  accessibility_login_redirect_url = null
  accessibility_self_service       = false
  admin_note                       = null
  app_links_json                   = null
  app_settings_json = jsonencode({
    app                = {}
    manualProvisioning = false
  })
  authentication_policy                = var.mcp_auth_policy_id
  auto_key_rotation                    = true
  auto_submit_toolbar                  = false
  backchannel_custom_authenticator_id  = null
  client_basic_secret                  = null # sensitive
  client_basic_secret_wo               = null # sensitive
  client_basic_secret_wo_version       = null
  client_id                            = var.mcp_client_id
  client_uri                           = null
  consent_method                       = "REQUIRED"
  enduser_note                         = null
  frontchannel_logout_session_required = false
  frontchannel_logout_uri              = null
  grant_types                          = ["client_credentials"]
  hide_ios                             = true
  hide_web                             = true
  implicit_assignment                  = false
  issuer_mode                          = "DYNAMIC"
  jwks_uri                             = null
  label                                = "svc-okta-identity-mcp"
  login_mode                           = "DISABLED"
  login_scopes                         = []
  login_uri                            = null
  logo                                 = null
  logo_uri                             = null
  participate_slo                      = false
  pkce_required                        = false
  policy_uri                           = null
  post_logout_redirect_uris            = []
  preconfigured_app                    = null
  profile                              = null
  redirect_uris                        = []
  response_types                       = ["token"]
  status                               = "ACTIVE"
  token_endpoint_auth_method           = "private_key_jwt"
  tos_uri                              = null
  type                                 = "service"
  user_name_template                   = "$${source.login}"
  user_name_template_push_status       = null
  user_name_template_suffix            = null
  user_name_template_type              = "BUILT_IN"
  wildcard_redirect                    = "DISABLED"
  jwks {
    e   = "AQAB"
    kid = var.mcp_jwks_kid
    kty = "RSA"
    n   = var.mcp_jwks_n
    x   = null
    y   = null
  }
}