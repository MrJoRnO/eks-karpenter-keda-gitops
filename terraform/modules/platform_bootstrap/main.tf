# =============================================================================
# Platform Bootstrap
# Install order: ArgoCD → Karpenter → KEDA → deploy ScaledJob via ArgoCD
# =============================================================================

# -----------------------------------------------------------------------------
# 1. ArgoCD (optional but included for full GitOps setup)
# -----------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.12"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }
  set {
    name  = "server.replicas"
    value = "1"
  }
  set {
    name  = "repoServer.replicas"
    value = "1"
  }
  # Keep ArgoCD on system nodes
  set {
    name  = "global.nodeSelector.role"
    value = "system"
  }
}

# -----------------------------------------------------------------------------
# 2. Karpenter
# -----------------------------------------------------------------------------
resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.1.1"
  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }
  set {
    name  = "settings.interruptionQueue"
    value = var.karpenter_interruption_queue
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.karpenter_controller_role_arn
  }
  # Keep Karpenter controller on system nodes
  set {
    name  = "nodeSelector.role"
    value = "system"
  }

  depends_on = [helm_release.argocd]
}

# -----------------------------------------------------------------------------
# 3. KEDA
# -----------------------------------------------------------------------------
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.16.0"
  namespace        = "keda"
  create_namespace = true

  # Keep KEDA controllers on system nodes
  set {
    name  = "operator.nodeSelector.role"
    value = "system"
  }
  set {
    name  = "metricsServer.nodeSelector.role"
    value = "system"
  }

  depends_on = [helm_release.karpenter]
}

# -----------------------------------------------------------------------------
# 4. Deploy NodePool + EC2NodeClass + ScaledJob via ArgoCD Application
#    Source: the k8s/ directory of the config repo.
#    Karpenter + KEDA CRDs must exist before ArgoCD tries to sync.
# -----------------------------------------------------------------------------
resource "null_resource" "argocd_apps" {
  triggers = {
    cluster_name = var.cluster_name
    job_role_arn = var.job_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e

      # Wait for ArgoCD server to become ready
      kubectl -n argocd rollout status deployment/argocd-server --timeout=120s

      # ArgoCD AppProject
      kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: sqs-job
  namespace: argocd
spec:
  sourceRepos: ["*"]
  destinations:
    - namespace: karpenter
      server: https://kubernetes.default.svc
    - namespace: sqs-processor
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: karpenter.sh
      kind: NodePool
    - group: karpenter.k8s.aws
      kind: EC2NodeClass
YAML

      # Karpenter NodePool + EC2NodeClass
      kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter-config
  namespace: argocd
spec:
  project: sqs-job
  source:
    repoURL: ${var.config_repo_url}
    targetRevision: main
    path: k8s/karpenter
  destination:
    server: https://kubernetes.default.svc
    namespace: karpenter
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML

      # ScaledJob namespace + manifests
      kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sqs-processor
  namespace: argocd
spec:
  project: sqs-job
  source:
    repoURL: ${var.config_repo_url}
    targetRevision: main
    path: k8s/scaled-job
  destination:
    server: https://kubernetes.default.svc
    namespace: sqs-processor
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
    EOF
  }

  depends_on = [helm_release.keda, helm_release.karpenter]
}

# -----------------------------------------------------------------------------
# 5. ConfigMap with runtime values (queue URL, bucket, role ARN)
#    ArgoCD syncs the ScaledJob but doesn't know these values at commit time.
# -----------------------------------------------------------------------------
resource "null_resource" "processor_config" {
  triggers = {
    sqs_queue_url  = var.sqs_queue_url
    s3_bucket_name = var.s3_bucket_name
    job_role_arn   = var.job_role_arn
  }

  provisioner "local-exec" {
    command = <<-EOF
      set -e

      kubectl create namespace sqs-processor --dry-run=client -o yaml | kubectl apply -f -

      kubectl create configmap sqs-processor-config \
        --namespace=sqs-processor \
        --from-literal=QUEUE_URL=${var.sqs_queue_url} \
        --from-literal=BUCKET_NAME=${var.s3_bucket_name} \
        --dry-run=client -o yaml | kubectl apply -f -

      # Patch service account with IRSA annotation
      kubectl create serviceaccount sqs-processor \
        --namespace=sqs-processor \
        --dry-run=client -o yaml | kubectl apply -f -

      kubectl annotate serviceaccount sqs-processor \
        --namespace=sqs-processor \
        --overwrite \
        eks.amazonaws.com/role-arn=${var.job_role_arn}
    EOF
  }

  depends_on = [null_resource.argocd_apps]
}
