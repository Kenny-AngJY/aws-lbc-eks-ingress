resource "helm_release" "metrics-server" {
  count = 0
  name  = "metrics-server"

  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2" # chart version

  set {
    name  = "metrics.enabled"
    value = false
  }

  # depends_on = [aws_eks_fargate_profile.kube-system]
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.deploy_aws_load_balancer_controller_via_helm_provider ? 1 : 0
  name  = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.13.2" # chart version

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.AmazonEKSLoadBalancerController[0].arn
  }

  set {
    name  = "serviceAccount.name"
    value = var.aws_load_balancer_controller_service_account_name
  }

}
