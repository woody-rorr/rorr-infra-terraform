terraform {
  backend "s3" {
    bucket         = "rorr-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "rorr-terraform-lock"
    encrypt        = true
  }
}
