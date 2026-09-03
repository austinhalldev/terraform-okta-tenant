terraform {
  required_version = ">= 1.10"

  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 7.0"
    }
  }
}
