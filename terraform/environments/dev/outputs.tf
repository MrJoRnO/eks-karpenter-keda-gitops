output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "s3_bucket_name" {
  value = module.s3.bucket_name
}

output "github_ci_role_arn" {
  description = "Copy this ARN into GitHub Secret AWS_CI_ROLE_ARN"
  value       = module.iam.github_ci_role_arn
}
