terraform {
  required_version = ">= 1.11"

  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # See terraform/environments/hub/backend.tf for why this is here.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}