variable "env"                          { type = string }
variable "aws_region"                   { type = string }
variable "cluster_name"                 { type = string }
variable "cluster_endpoint"             { type = string }
variable "karpenter_controller_role_arn" { type = string }
variable "karpenter_node_role_name"     { type = string }
variable "karpenter_interruption_queue" { type = string }
variable "job_role_arn"                 { type = string }
variable "keda_operator_role_arn"       { type = string }
variable "sqs_queue_url"                { type = string }
variable "s3_bucket_name"               { type = string }
variable "ecr_registry"                 { type = string }
variable "config_repo_url" {
  type    = string
  default = "https://github.com/MrJoRnO/eks-karpenter-keda-gitops"
}
