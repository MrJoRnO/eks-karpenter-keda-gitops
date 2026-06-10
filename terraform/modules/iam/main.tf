data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  oidc_host = replace(var.cluster_oidc_url, "https://", "")
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.name
}

# =============================================================================
# 1. Karpenter node role
#    IAM role attached to EC2 instances Karpenter launches.
#    No OIDC — this is a standard EC2 instance profile role.
# =============================================================================
resource "aws_iam_role" "karpenter_node" {
  name = "${var.env}-karpenter-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.env}-karpenter-node-profile"
  role = aws_iam_role.karpenter_node.name
}

# =============================================================================
# 2. Karpenter controller IRSA
#    Allows the Karpenter pod to manage EC2 instances and read cluster state.
# =============================================================================
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.env}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.env}-karpenter-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:*::image/*",
          "arn:aws:ec2:*::snapshot/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:launch-template/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2InstanceActionsWithTags"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:launch-template/*"]
        Action   = ["ec2:CreateLaunchTemplate", "ec2:DeleteLaunchTemplate", "ec2:TerminateInstances"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceCreationTagging"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:launch-template/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*:*:network-interface/*", "arn:aws:ec2:*:*:spot-instances-request/*"]
        Action   = ["ec2:CreateTags"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowMachineDeletion"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowEC2ReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:aws:ssm:*::parameter/aws/service/*"
        Action   = ["ssm:GetParameter"]
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["pricing:GetProducts"]
      },
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Resource = var.interruption_queue_arn
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Resource = aws_iam_role.karpenter_node.arn
        Action   = ["iam:PassRole"]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        Sid      = "AllowEKSAccess"
        Effect   = "Allow"
        Resource = "arn:aws:eks:${local.region}:${local.account}:cluster/${var.cluster_name}"
        Action   = ["eks:DescribeCluster"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# =============================================================================
# 3. Job IRSA — for ScaledJob pods (SQS receive/delete + S3 put)
#    Also used by KEDA's SQS scaler to read queue depth.
# =============================================================================
data "aws_iam_policy_document" "job_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:sqs-processor:sqs-processor"]
    }
  }
}

resource "aws_iam_role" "job" {
  name               = "${var.env}-sqs-job-role"
  assume_role_policy = data.aws_iam_policy_document.job_assume.json
}

resource "aws_iam_policy" "job" {
  name = "${var.env}-sqs-job-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.s3_bucket_arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "job" {
  role       = aws_iam_role.job.name
  policy_arn = aws_iam_policy.job.arn
}

# =============================================================================
# 4. GitHub OIDC — lets GitHub Actions push to ECR without static keys
# =============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_app_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "${var.env}-github-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

resource "aws_iam_policy" "github_ci" {
  name = "${var.env}-github-ci-ecr-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = "arn:aws:ecr:*:*:repository/platform/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_ci" {
  role       = aws_iam_role.github_ci.name
  policy_arn = aws_iam_policy.github_ci.arn
}
