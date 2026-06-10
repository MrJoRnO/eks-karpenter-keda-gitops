ENV        ?= dev
TFVARS     := $(ENV).tfvars
STATE_KEY  := $(ENV)/terraform.tfstate
BACKEND    := -backend-config="key=$(STATE_KEY)"

.PHONY: init plan apply apply-infra apply-platform destroy fmt validate help

help:
	@echo "Usage: make <target> [ENV=dev|staging|prod]"
	@echo ""
	@echo "  init            terraform init with correct backend key"
	@echo "  plan            terraform plan"
	@echo "  apply           two-stage apply (infra → platform)"
	@echo "  apply-infra     stage 1: VPC + EKS + SQS + S3 + ECR + IAM"
	@echo "  apply-platform  stage 2: ArgoCD + Karpenter + KEDA"
	@echo "  destroy         destroy all resources"

init:
	terraform init -reconfigure $(BACKEND)

plan: init
	terraform plan -var-file=$(TFVARS)

apply: apply-infra apply-platform
	@echo "✓ Full apply complete for ENV=$(ENV)"

apply-infra: init
	@echo ">>> Stage 1: Infrastructure (VPC, EKS, SQS, S3, ECR, IAM)"
	terraform apply -var-file=$(TFVARS) \
		-target=module.vpc \
		-target=module.eks \
		-target=module.sqs \
		-target=module.s3 \
		-target=module.ecr \
		-target=module.iam \
		-target=aws_eks_access_entry.karpenter_nodes \
		-target=time_sleep.wait_for_cluster
	@echo "✓ Stage 1 complete"

apply-platform: init
	@echo ">>> Stage 2: Platform (ArgoCD + Karpenter + KEDA)"
	terraform apply -var-file=$(TFVARS)
	@echo "✓ Stage 2 complete"

destroy: init
	terraform destroy -var-file=$(TFVARS)

fmt:
	terraform fmt -recursive .

validate: init
	terraform validate
