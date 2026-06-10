variable "env"              { type = string }
variable "cluster_name"     { type = string }
variable "cluster_oidc_arn" { type = string }
variable "cluster_oidc_url" { type = string }
variable "sqs_queue_arn"    { type = string }
variable "s3_bucket_arn"    { type = string }
variable "interruption_queue_arn" {
  type    = string
  default = ""
}
variable "github_org"      { type = string }
variable "github_app_repo" { type = string }

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false when the provider already exists in the account (one per account)."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "ARN of the existing GitHub OIDC provider. Required when create_github_oidc_provider = false."
  type        = string
  default     = ""
}
