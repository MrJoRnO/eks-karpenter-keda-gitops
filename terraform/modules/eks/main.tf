module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  enable_irsa         = true
  authentication_mode = "API_AND_CONFIG_MAP"

  # System nodes only — Spot/Karpenter nodes are not managed node groups
  eks_managed_node_groups = {
    system = {
      name           = "${var.env}-system-nodes"
      instance_types = var.system_node_group.instance_types
      min_size       = var.system_node_group.desired_size
      max_size       = var.system_node_group.desired_size + 1
      desired_size   = var.system_node_group.desired_size

      labels = { role = "system" }
    }
  }

  # karpenter.sh/discovery on cluster lets EC2NodeClass discover security groups
  tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
}

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "terraform_runner" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_runner_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope { type = "cluster" }

  depends_on = [aws_eks_access_entry.terraform_runner]
}
