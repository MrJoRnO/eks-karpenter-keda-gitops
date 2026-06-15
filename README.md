# eks-karpenter-keda-gitops

Infrastructure and GitOps configuration for a production-grade EKS platform that runs event-driven Kubernetes Jobs. SQS messages trigger KEDA to create Jobs, Karpenter provisions Spot EC2 nodes on demand, and ArgoCD keeps the cluster state in sync with this repository.

## Architecture

```
SQS Queue
    │
    ▼  (queue depth polled by KEDA)
KEDA ScaledJob ──► creates Job ──► Pod runs sqs-to-s3-worker ──► S3 Bucket
                                          │
                               Karpenter provisions
                               Spot EC2 node if needed
```

This repo follows the **two-repo GitOps pattern**:
- `sqs-to-s3-worker` — application code + CI/CD pipeline (pushes image to ECR, updates image tag here)
- `eks-karpenter-keda-gitops` (this repo) — infrastructure + Kubernetes manifests (ArgoCD syncs from here)

## Features

- Modular Terraform with isolated `dev` and `prod` environments
- Two-stage apply: infrastructure first (`apply-infra`), platform tooling second (`apply-platform`)
- Karpenter v1 provisioning Spot nodes via EC2NodeClass + NodePool with Kustomize overlays
- KEDA v2 ScaledJob with SQS trigger using IRSA (`identityOwner: operator`)
- ArgoCD managing both Karpenter config and the application ScaledJob
- Keyless AWS authentication for GitHub Actions via OIDC — no static IAM keys anywhere
- Remote Terraform state in S3 with DynamoDB locking

## Tech Stack

| Layer | Technology |
|---|---|
| Cloud | AWS (EKS, SQS, S3, ECR, VPC, IAM) |
| Infrastructure as Code | Terraform >= 1.6 |
| Kubernetes | EKS 1.31 |
| Node Provisioning | Karpenter v1.1.1 |
| Event-Driven Scaling | KEDA v2.16 |
| GitOps | ArgoCD (Helm chart 7.6.12) |
| Manifest Templating | Kustomize (base + overlays) |
| CI Auth | GitHub Actions OIDC |

## Repository Structure

```
.
├── terraform/
│   ├── Makefile                      # Convenience targets (make apply ENV=dev)
│   ├── environments/
│   │   ├── dev/                      # Dev environment root (backend, providers, main, vars)
│   │   └── prod/                     # Prod environment root
│   └── modules/
│       ├── vpc/                      # VPC, subnets, NAT gateway
│       ├── eks/                      # EKS cluster + managed node group (system nodes)
│       ├── sqs/                      # SQS queue + Karpenter interruption queue
│       ├── s3/                       # S3 bucket for processed messages
│       ├── ecr/                      # ECR repository
│       ├── iam/                      # All IRSA roles: Karpenter, KEDA, job worker, GitHub CI
│       └── platform_bootstrap/       # ArgoCD + Karpenter + KEDA Helm installs via Terraform
├── infra/
│   └── karpenter/
│       ├── base/                     # EC2NodeClass + NodePool (environment-agnostic)
│       └── overlays/{dev,prod}/      # instanceProfile + subnet/SG tag patches per environment
└── apps/
    ├── base/                         # ScaledJob + TriggerAuthentication
    └── overlays/{dev,prod}/          # Queue URL patch + image tag (updated by CD pipeline)
```

## Getting Started

### Prerequisites

- Terraform >= 1.6
- AWS CLI v2, configured with sufficient IAM permissions
- `kubectl`
- `make`

### Installation

```bash
git clone https://github.com/MrJoRnO/eks-karpenter-keda-gitops.git
cd eks-karpenter-keda-gitops/terraform
```

### Usage

**Stage 1 — Provision infrastructure**

```bash
make init ENV=dev
make apply-infra ENV=dev
```

Creates: VPC, EKS cluster, SQS queues, S3 bucket, ECR repository, and all IAM/IRSA roles.

**Update kubeconfig after Stage 1**

```bash
aws eks update-kubeconfig --name sqs-job-dev --region eu-central-1
kubectl get nodes
```

**Stage 2 — Install platform tooling**

```bash
make apply-platform ENV=dev
```

Installs ArgoCD, Karpenter, and KEDA via Helm, then deploys the ArgoCD Applications that sync `infra/karpenter/overlays/dev` and `apps/overlays/dev` from this repository.

**Access ArgoCD**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Open [https://localhost:8080](https://localhost:8080) with user `admin`.

**End-to-end verification**

```bash
# Send a test message
aws sqs send-message \
  --queue-url "https://sqs.eu-central-1.amazonaws.com/<account-id>/sqs-job-dev-messages" \
  --message-body "e2e test" \
  --region eu-central-1

# Watch KEDA trigger a Job and Karpenter provision a Spot node
kubectl get pods -n sqs-processor -w

# Confirm the message landed in S3
aws s3 ls s3://sqs-job-dev-messages-194636597980 --region eu-central-1
```

### Makefile Targets

```bash
make help                  # List all targets
make init    ENV=dev       # terraform init
make plan    ENV=dev       # terraform plan
make apply   ENV=dev       # Full two-stage apply (infra + platform)
make apply-infra   ENV=dev # Stage 1: VPC + EKS + SQS + S3 + ECR + IAM
make apply-platform ENV=dev# Stage 2: ArgoCD + Karpenter + KEDA
make destroy ENV=dev       # Destroy all resources
make fmt                   # Format all .tf files recursively
make validate ENV=dev      # Validate the selected environment
```

## GitOps Flow

```
Push to sqs-to-s3-worker (dev branch)
    │
    ▼
GitHub Actions CI — ruff lint + pytest
    │
    ▼
GitHub Actions CD — docker build + Trivy scan + push to ECR
    │
    ▼
CD commits new image tag to apps/overlays/dev/kustomization.yaml (this repo)
    │
    ▼
ArgoCD detects change, syncs ScaledJob to cluster
    │
    ▼
KEDA triggers Job on next SQS message, Karpenter provisions Spot node if needed
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Commit changes and open a pull request targeting `dev`
4. Infrastructure changes should include a `terraform plan` output in the PR description


