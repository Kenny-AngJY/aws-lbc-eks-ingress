resource "helm_release" "metrics-server" {
  count = 0
  name  = "metrics-server"

  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.13.0" # chart version

  set = [
    {
      # If true, allow unauthenticated access to /metrics.
      name  = "metrics.enabled"
      value = false
    }
  ]

  # depends_on = [aws_eks_fargate_profile.kube-system]
}

resource "helm_release" "aws_load_balancer_controller" {
  count = var.deploy_aws_load_balancer_controller_via_helm_provider ? 1 : 0
  name  = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "3.0.0" # chart version

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.AmazonEKSLoadBalancerController[0].arn
    },
    {
      name  = "serviceAccount.name"
      value = var.aws_load_balancer_controller_service_account_name
    },
    {
      name  = "vpcId"
      value = module.vpc[0].vpc_id
    }
  ]
}
