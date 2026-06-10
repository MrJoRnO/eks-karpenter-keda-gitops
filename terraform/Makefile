ENV ?= dev
DIR  = environments/$(ENV)

.PHONY: init plan apply apply-infra apply-platform destroy fmt validate help

help:
	@echo "Usage: make <target> [ENV=dev|prod]"
	@echo ""
	@echo "  init            terraform init for the selected environment"
	@echo "  plan            terraform plan"
	@echo "  apply           two-stage apply (infra → platform)"
	@echo "  apply-infra     stage 1: VPC + EKS + SQS + S3 + ECR + IAM"
	@echo "  apply-platform  stage 2: ArgoCD + Karpenter + KEDA"
	@echo "  destroy         destroy all resources"
	@echo "  fmt             format all Terraform files"
	@echo "  validate        validate the selected environment"

init:
	terraform -chdir=$(DIR) init -reconfigure

plan: init
	terraform -chdir=$(DIR) plan

apply: apply-infra apply-platform
	@echo "✓ Full apply complete for ENV=$(ENV)"

apply-infra: init
	@echo ">>> Stage 1: Infrastructure (VPC, EKS, SQS, S3, ECR, IAM)"
	terraform -chdir=$(DIR) apply \
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
	terraform -chdir=$(DIR) apply
	@echo "✓ Stage 2 complete"

destroy: init
	terraform -chdir=$(DIR) destroy

fmt:
	terraform fmt -recursive environments/ modules/

validate: init
	terraform -chdir=$(DIR) validate
