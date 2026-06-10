variable "env" {
  description = "Target environment: dev | staging | prod"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be dev, staging, or prod"
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "github_org" {
  description = "GitHub organisation or username (used for OIDC trust policy)"
  type        = string
}

variable "github_app_repo" {
  description = "Name of the application repository"
  type        = string
  default     = "sqs-to-s3-job"
}
