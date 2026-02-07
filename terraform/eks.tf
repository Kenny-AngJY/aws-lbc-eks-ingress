module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "21.14.0" # Published January 13, 2026
  create                                 = true
  name                                   = local.cluster_name
  kubernetes_version                     = "1.34"
  authentication_mode                    = "API"
  endpoint_private_access                = true # Indicates whether or not the Amazon EKS private API server endpoint is enabled
  endpoint_public_access                 = true # Indicates whether or not the Amazon EKS public API server endpoint is enabled
  endpoint_public_access_cidrs           = ["0.0.0.0/0"]
  cloudwatch_log_group_retention_in_days = 30
  create_kms_key                         = var.create_kms_key
  enable_irsa                            = true # Determines whether to create an OpenID Connect Provider for EKS to enable IRSA

  encryption_config = {}

  compute_config = {
    enabled    = var.enable_auto_mode
    # node_pools = ["general-purpose"] # Comment this line out when var.enable_auto_mode is false
  }

  addons = var.enable_auto_mode ? {} : {
    coredns = {
      before_compute = true
      most_recent    = true
      #addon_version  = "v1.12.4-eksbuild.1"
    }
    # kube-proxy pod (that is deployed as a daemonset) shares the same IPv4 address as the node it's on.
    kube-proxy = {
      before_compute = true
      most_recent    = true
      #addon_version  = "v1.34.1-eksbuild.2"
    }
    # Network interface will show all IPs used in the subnet
    # VPC CNI add-on will create the "aws-node" daemonset in the kube-system namespace.
    vpc-cni = {
      before_compute = true
      most_recent    = true
      #addon_version            = "v1.21.1-eksbuild.1" # major-version.minor-version.patch-version-eksbuild.build-number.
      service_account_role_arn = aws_iam_role.eks_vpc_cni_role[0].arn
      configuration_values = jsonencode(
        {
          enableNetworkPolicy = "true" # To enable using the NetworkPolicy controller
          env = {
            # https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
            # https://github.com/aws/amazon-vpc-cni-k8s/blob/master/README.md
            # kubectl get ds aws-node -n kube-system -o yaml
            WARM_IP_TARGET    = "3" # Specifies the number of free IP addresses that the ipamd daemon should attempt to keep available for pod assignment on the node.
            MINIMUM_IP_TARGET = "3" # Specifies the number of total IP addresses that the ipamd daemon should attempt to allocate for pod assignment on the node.
            # ENABLE_PREFIX_DELEGATION = true # To enable prefix delegation on nitro instances. Setting ENABLE_PREFIX_DELEGATION to true will start allocating a prefix (/28 for IPv4 and /80 for IPv6) instead of a secondary IP in the ENIs subnet.
            # NETWORK_POLICY_ENFORCING_MODE = "strict" # strict | standard
          }
        }
      )
    }
  }

  vpc_id = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  /* -----------------------------------------------------------------------------------
  A list of subnet IDs where the nodes/node groups will be provisioned.
  If control_plane_subnet_ids is not provided, the EKS cluster control plane (ENIs) will be provisioned in these subnets
  ----------------------------------------------------------------------------------- */
  subnet_ids = var.create_vpc ? ((var.use_fargate_profile || var.create_eks_worker_nodes_in_private_subnet) ? module.vpc[0].list_of_private_subnet_ids : module.vpc[0].list_of_public_subnet_ids) : var.list_of_subnet_ids

  /* -----------------------------------------------------------------------------------
  A list of subnet IDs where the EKS Managed ENIs will be provisioned.
  Used for expanding the pool of subnets used by nodes/node groups without replacing the EKS control plane
  ----------------------------------------------------------------------------------- */
  control_plane_subnet_ids = var.create_vpc ? (var.create_eks_worker_nodes_in_private_subnet ? module.vpc[0].list_of_private_subnet_ids : module.vpc[0].list_of_public_subnet_ids) : var.list_of_subnet_ids

  # EKS Managed Node Group(s)
  eks_managed_node_groups = var.use_fargate_profile || var.enable_auto_mode ? {} : {
    eks_managed_NG1 = {
      min_size = 1
      max_size = 2
      /*
      desired_size is ignored after the initial creation
      https://github.com/bryantbiggs/eks-desired-size-hack
      */
      desired_size  = 1
      capacity_type = "SPOT"
    }
  }

  # Fargate Profile(s)
  fargate_profiles = var.use_fargate_profile ? {
    # Disabled logging because aws-logging configmap was not found. configmap "aws-logging" not found
    fargate_profile_1 = {
      name            = "fargate_profile_1"
      create_iam_role = false
      # AWS Fargate can only use private subnets with NAT gateway to deploy your pods.
      subnets_ids = module.vpc[0].list_of_private_subnet_ids[0]

      tags = {
        Owner = "test"
      }
    }
  } : {}

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  ## https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  enabled_log_types = [
    "audit",
    "api",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  deletion_protection = false
  tags = local.default_tags
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  count                       = var.create_aws_ebs_csi_driver_add_on ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.53.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE

  service_account_role_arn = aws_iam_role.amazon_EBS_CSI_iam_role[0].arn
}

/*
Add a deployment called "amazon-cloudwatch-observability-controller-manager"
Adds a ds called "cloudwatch-agent" and "fluent-bit"
Adds CRDs, "amazoncloudwatchagents.cloudwatch.aws.amazon.com", "dcgmexporters.cloudwatch.aws.amazon.com", "instrumentations.cloudwatch.aws.amazon.com", "neuronmonitors.cloudwatch.aws.amazon.com", 

The container logs are sent to CloudWatch Logs with the log group name /aws/containerinsights/<cluster-name>/application
*/
resource "aws_eks_addon" "amazon_cloudwatch_observability" {
  count                       = var.create_amazon_cloudwatch_observability_add_on ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = "v4.7.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE

  service_account_role_arn = aws_iam_role.CloudWatchAgent[0].arn

  # configuration_values = jsonencode({
  #   replicaCount = 4
  #   resources = {
  #     limits = {
  #       cpu    = "100m"
  #       memory = "150Mi"
  #     }
  #     requests = {
  #       cpu    = "100m"
  #       memory = "150Mi"
  #     }
  #   }
  # })
  depends_on = [module.eks]
}

resource "aws_security_group_rule" "node_port" {
  count             = var.create_eks_worker_nodes_in_private_subnet ? 0 : 1
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.node_security_group_id
}

output "eks_managed_node_groups_autoscaling_group_names" {
  value = module.eks.eks_managed_node_groups_autoscaling_group_names
}

output "cluster_primary_security_group_id" {
  value = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "eks_worker_node_subnet" {
  description = "Inform users of the subnet where the EKS worker nodes are deployed."
  value       = (var.use_fargate_profile || var.create_eks_worker_nodes_in_private_subnet) ? "Private" : "Public"
}

# output "eks_managed_node_groups" {
#   description = "Map of attribute maps for all EKS managed node groups created."
#   value       = module.eks.eks_managed_node_groups
# }