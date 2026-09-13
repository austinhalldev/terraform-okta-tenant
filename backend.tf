terraform {
  backend "s3" {
    bucket       = "ah-terraform-okta-tenant-state"
    key          = "okta-tenant/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}