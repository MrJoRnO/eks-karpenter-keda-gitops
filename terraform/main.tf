# =============================================================================
# Root module — SQS-to-S3 job infrastructure.
# Apply order: make apply-infra ENV=dev → make apply-platform ENV=dev
# =============================================================================

# -----------------------------------------------------------------------------
# 1. VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  vpc_name        = "${local.cluster_name}-vpc"
  vpc_cidr        = local.cfg.vpc_cidr
  azs             = local.cfg.azs
  private_subnets = local.cfg.private_subnets
  public_subnets  = local.cfg.public_subnets
  single_nat_gw   = local.cfg.single_nat_gw
  cluster_name    = local.cluster_name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 2. EKS cluster
#    System node group for platform components (ArgoCD, Karpenter, KEDA).
#    Spot nodes are provisioned on-demand by Karpenter.
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  env          = var.env
  cluster_name = local.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets

  cluster_endpoint_public_access = local.cfg.cluster_endpoint_public_access
  system_node_group              = local.cfg.system_node_group

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 3. SQS queue — receives messages for the job to process
# -----------------------------------------------------------------------------
module "sqs" {
  source = "./modules/sqs"

  queue_name   = "${local.cluster_name}-messages"
  cluster_name = local.cluster_name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 4. S3 bucket — stores processed messages as timestamped .txt files
# -----------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  bucket_name = "${local.cluster_name}-messages-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 5. ECR repository for the job container image
# -----------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  repository_name = "platform/sqs-to-s3-job"
  tags            = local.common_tags
}

# -----------------------------------------------------------------------------
# 6. IAM — IRSA roles + Karpenter node role + GitHub OIDC
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  env              = var.env
  cluster_name     = local.cluster_name
  cluster_oidc_arn = module.eks.cluster_oidc_arn
  cluster_oidc_url = module.eks.cluster_oidc_url

  sqs_queue_arn          = module.sqs.queue_arn
  s3_bucket_arn          = module.s3.bucket_arn
  interruption_queue_arn = module.sqs.interruption_queue_arn

  github_org      = var.github_org
  github_app_repo = var.github_app_repo
}

# Access entry so Karpenter-managed nodes can join the cluster
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.iam.karpenter_node_role_arn
  type          = "EC2_LINUX"

  depends_on = [module.eks, module.iam]
}

# -----------------------------------------------------------------------------
# 7. API server readiness gate (same reason as base project)
# -----------------------------------------------------------------------------
resource "time_sleep" "wait_for_cluster" {
  create_duration = "60s"
  depends_on      = [module.eks, aws_eks_access_entry.karpenter_nodes]
}

# -----------------------------------------------------------------------------
# 8. Platform bootstrap — ArgoCD, Karpenter, KEDA
# -----------------------------------------------------------------------------
module "platform_bootstrap" {
  source = "./modules/platform_bootstrap"

  env        = var.env
  aws_region = var.aws_region

  cluster_name                  = local.cluster_name
  cluster_endpoint              = module.eks.cluster_endpoint
  karpenter_controller_role_arn = module.iam.karpenter_controller_role_arn
  karpenter_node_role_name      = module.iam.karpenter_node_role_name
  karpenter_interruption_queue  = module.sqs.interruption_queue_name
  job_role_arn                  = module.iam.job_role_arn
  sqs_queue_url                 = module.sqs.queue_url
  s3_bucket_name                = module.s3.bucket_name
  ecr_registry                  = module.ecr.registry_url

  depends_on = [time_sleep.wait_for_cluster]
}
