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
