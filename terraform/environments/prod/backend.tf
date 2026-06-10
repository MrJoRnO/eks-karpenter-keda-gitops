terraform {
  backend "s3" {
    bucket         = "platform-terraform-state-v1"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "platform-terraform-locks-v1"
    encrypt        = true
  }
}
