output "karpenter_node_role_arn"       { value = aws_iam_role.karpenter_node.arn }
output "karpenter_node_role_name"      { value = aws_iam_role.karpenter_node.name }
output "karpenter_node_profile_name"   { value = aws_iam_instance_profile.karpenter_node.name }
output "karpenter_controller_role_arn" { value = aws_iam_role.karpenter_controller.arn }
output "job_role_arn"                  { value = aws_iam_role.job.arn }
output "github_ci_role_arn"            { value = aws_iam_role.github_ci.arn }
