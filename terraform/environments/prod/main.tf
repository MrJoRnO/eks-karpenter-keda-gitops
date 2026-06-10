# =============================================================================
# Prod environment — SQS-to-S3 job infrastructure
# Apply order: make apply-infra ENV=prod → make apply-platform ENV=prod
# =============================================================================

locals {
  env          = "prod"
  aws_region   = "eu-central-1"
  cluster_name = "sqs-job-prod"

  common_tags = {
    Environment = local.env
    Project     = "sqs-to-s3-job"
    ManagedBy   = "terraform"
  }
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "this" {
  name       = local.cluster_name
  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# 1. VPC — 3 AZs, one NAT GW per AZ for high availability
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_name        = "${local.cluster_name}-vpc"
  vpc_cidr        = "10.2.0.0/16"
  azs             = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  private_subnets = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  public_subnets  = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
  single_nat_gw   = false
  cluster_name    = local.cluster_name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 2. EKS cluster
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  env          = local.env
  cluster_name = local.cluster_name
  aws_region   = local.aws_region
  vpc_id       = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets

  cluster_endpoint_public_access = false
  system_node_group = {
    instance_types = ["t3.large"]
    desired_size   = 2
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 3. SQS queue
# -----------------------------------------------------------------------------
module "sqs" {
  source = "../../modules/sqs"

  queue_name   = "${local.cluster_name}-messages"
  cluster_name = local.cluster_name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 4. S3 bucket
# -----------------------------------------------------------------------------
module "s3" {
  source = "../../modules/s3"

  bucket_name = "${local.cluster_name}-messages-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 5. ECR repository
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  repository_name = "platform/sqs-to-s3-job"
  tags            = local.common_tags
}

# -----------------------------------------------------------------------------
# 6. IAM — GitHub OIDC provider already exists (created in dev env, one per account)
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  env              = local.env
  cluster_name     = local.cluster_name
  cluster_oidc_arn = module.eks.cluster_oidc_arn
  cluster_oidc_url = module.eks.cluster_oidc_url

  sqs_queue_arn          = module.sqs.queue_arn
  s3_bucket_arn          = module.s3.bucket_arn
  interruption_queue_arn = module.sqs.interruption_queue_arn

  github_org                  = var.github_org
  github_app_repo             = "sqs-to-s3-worker"
  create_github_oidc_provider = false
  github_oidc_provider_arn    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# Access entry so Karpenter-managed nodes can join the cluster
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.iam.karpenter_node_role_arn
  type          = "EC2_LINUX"

  depends_on = [module.eks, module.iam]
}

# API server readiness gate
resource "time_sleep" "wait_for_cluster" {
  create_duration = "60s"
  depends_on      = [module.eks, aws_eks_access_entry.karpenter_nodes]
}

# -----------------------------------------------------------------------------
# 7. Platform bootstrap — ArgoCD, Karpenter, KEDA
# -----------------------------------------------------------------------------
module "platform_bootstrap" {
  source = "../../modules/platform_bootstrap"

  env        = local.env
  aws_region = local.aws_region

  cluster_name                  = local.cluster_name
  cluster_endpoint              = module.eks.cluster_endpoint
  karpenter_controller_role_arn = module.iam.karpenter_controller_role_arn
  karpenter_node_role_name      = module.iam.karpenter_node_role_name
  karpenter_interruption_queue  = module.sqs.interruption_queue_name
  job_role_arn                  = module.iam.job_role_arn
  keda_operator_role_arn        = module.iam.keda_operator_role_arn
  sqs_queue_url                 = module.sqs.queue_url
  s3_bucket_name                = module.s3.bucket_name
  ecr_registry                  = module.ecr.registry_url

  depends_on = [time_sleep.wait_for_cluster]
}
