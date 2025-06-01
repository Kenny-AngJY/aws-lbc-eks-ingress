module "eks" {
  source                                 = "terraform-aws-modules/eks/aws"
  version                                = "20.33.0" # Published January 18, 2025
  create                                 = true
  cluster_name                           = local.cluster_name
  cluster_version                        = "1.33"
  authentication_mode                    = "API"
  cluster_endpoint_private_access        = true # Indicates whether or not the Amazon EKS private API server endpoint is enabled
  cluster_endpoint_public_access         = true # Indicates whether or not the Amazon EKS public API server endpoint is enabled
  cluster_endpoint_public_access_cidrs   = ["0.0.0.0/0"]
  cloudwatch_log_group_retention_in_days = 30
  create_kms_key                         = var.create_kms_key
  enable_irsa                            = true # Determines whether to create an OpenID Connect Provider for EKS to enable IRSA

  /* -----------------------------------------------------------------------------------
  Install default unmanaged add-ons, such as aws-cni, kube-proxy, and CoreDNS during cluster creation. 
  If false, you must manually install desired add-ons (via the console, especially the Amazon VPC CNI add-on), 
  else even though your worker nodes will join the cluster, it will fail to be ready, showing the error:
  "container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized"
  
  Changing this value will force a new cluster to be created.
  ----------------------------------------------------------------------------------- */
  bootstrap_self_managed_addons = true

  # cluster_encryption_config = {
  #   "provider_key_arn" : var.kms_key_arn
  #   "resources" : ["secrets"]
  # }
  cluster_encryption_config = {}

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    # kube-proxy pod (that is deployed as a daemonset) shares the same IPv4 address as the node it's on.
    kube-proxy = {
      addon_version = "v1.33.0-eksbuild.2"
    }
    # Network interface will show all IPs used in the subnet
    # VPC CNI add-on will create the "aws-node" daemonset in the kube-system namespace.
    vpc-cni = {
      addon_version            = "v1.19.5-eksbuild.1" # major-version.minor-version.patch-version-eksbuild.build-number.
      service_account_role_arn = aws_iam_role.eks_vpc_cni_role.arn
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

  # self_managed_node_group_defaults = {
  #   instance_types = ["t3.medium", "t3.large"]
  #   # t3.medium: 2 vCPU, 4GiB
  #   # t3.large: 2 vCPU, 8GiB
  # }

  # self_managed_node_groups = {
  #   self_managed_NG1 = {
  #     desired_capacity = 2
  #     max_capacity     = 2
  #     min_capacity     = 1
  #     instance_types   = ["t3.medium", "t3.large"]
  #     capacity_type    = "SPOT" # ON_DEMAND | SPOT
  #   }
  # }

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["t3.medium", "t3.large"]
    # t3.medium: 2 vCPU, 4GiB
    # t3.large: 2 vCPU, 8GiB

    # iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"]
    update_config = {
      max_unavailable_percentage = 50
      # max_unavailable = 2
    }

    block_device_mappings = [{
      device_name = "/dev/xvda"
      ebs = {
        encrypted   = true
        volume_type = "gp3"
      }
    }]
  }

  eks_managed_node_groups = var.use_fargate_profile ? {} : {
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
  fargate_profile_defaults = {
    iam_role_arn = aws_iam_role.AmazonEKSFargatePodExecutionRole.arn
    timeouts = {
      create = "15m"
      delete = "15m"
    }
    selectors = [
      {
        namespace = "kube-system"
        # labels = {
        #   k8s-app = "kube-dns"
        # }
      },
      {
        # You have not defined any labels for pod selection. All Fargate compatible pods from this namespace will run on Fargate using this profile.
        namespace = "default"
      }
    ]
    #  iam_role_additional_policies = {
    #    additional = aws_iam_policy.additional.arn
    #  }
  }

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

  # access_entries = {
  #   # One access entry with a policy associated
  #   example = {
  #     kubernetes_groups = []
  #     principal_arn     = "arn:aws:iam::123456789012:role/something"

  #     policy_associations = {
  #       example = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  #         access_scope = {
  #           namespaces = ["default"]
  #           type       = "namespace"
  #         }
  #       }
  #     }
  #   }
  # }
  ## https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  cluster_enabled_log_types = [
    "audit",
    "api",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = local.default_tags
}

/*

*/
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  count                       = var.create_aws_ebs_csi_driver_add_on ? 1 : 0
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.44.0-eksbuild.1"
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
  addon_version               = "v4.1.0-eksbuild.1"
  resolve_conflicts_on_update = "OVERWRITE" # NONE | OVERWRITE | PRESERVE

  # Add-on does not support EKS Pod Identity at this time. Please use IAM roles for service accounts (IRSA) with this add-on.
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
  depends_on = [ module.eks ]
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