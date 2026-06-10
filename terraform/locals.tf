locals {
  env_config = {
    dev = {
      vpc_cidr        = "10.0.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b"]
      private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
      public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
      single_nat_gw   = true

      cluster_endpoint_public_access = true
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
    }

    staging = {
      vpc_cidr        = "10.1.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b"]
      private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]
      public_subnets  = ["10.1.101.0/24", "10.1.102.0/24"]
      single_nat_gw   = true

      cluster_endpoint_public_access = true
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
    }

    prod = {
      vpc_cidr        = "10.2.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
      private_subnets = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
      public_subnets  = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
      single_nat_gw   = false

      cluster_endpoint_public_access = false
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
    }
  }

  cfg          = local.env_config[var.env]
  cluster_name = "sqs-job-${var.env}"

  common_tags = {
    Environment = var.env
    Project     = "sqs-to-s3-job"
    ManagedBy   = "terraform"
  }
}
