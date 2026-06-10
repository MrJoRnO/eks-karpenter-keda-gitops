terraform {
  backend "s3" {
    bucket         = "platform-terraform-state-v1"
    region         = "eu-central-1"
    dynamodb_table = "platform-terraform-locks-v1"
    encrypt        = true
    # key provided at init time: make init ENV=dev
  }
}
