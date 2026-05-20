terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "rorr-tfstate-239460481239-us-east-1"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rorr-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "rorr-dev"
}
