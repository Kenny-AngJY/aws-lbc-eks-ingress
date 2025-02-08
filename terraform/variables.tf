variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "create_vpc" {
  description = "Choose whether to create a new VPC."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "If create_vpc is false, define your own vpc_id."
  type        = string
  default     = ""
}

variable "list_of_subnet_ids" {
  description = "If create_vpc is false, define your own subnet_ids."
  type        = list(string)
  default     = []
}

variable "create_kms_key" {
  description = "Controls if a KMS key for cluster encryption should be created."
  type        = bool
  default     = false
}

# variable "kms_key_arn" {
#   type    = string
#   default = "arn:aws:kms:<region>:<account-id>:key/xxx"
# }

variable "use_eks_pod_identity_agent" {
  description = "Use IAM Roles for Service Account (IRSA) by default."
  type        = bool
  default     = false
}

variable "create_eks_worker_nodes_in_private_subnet" {
  type    = bool
  default = false
}

variable "use_fargate_profile" {
  description = <<EOF
  Defaults to false to use node group. 
  If true, creates fargates profiles instead. 
  Will force "create_eks_worker_nodes_in_private_subnet" to 
  be true if "use_fargate_profile" is true.
  EOF
  type        = bool
  default     = false
}

variable "create_aws_ebs_csi_driver_add_on" {
  description = "Create the aws_ebs_csi_driver add-on for EKS."
  type        = bool
  default     = false
}

variable "create_amazon_cloudwatch_observability_add_on" {
  description = "Create the amazon_cloudwatch_observability add-on for EKS."
  type        = bool
  default     = false
}

variable "create_aws_load_balancer_controller_iam_resources" {
  description = <<EOF
  Create IAM resources for the aws_load_balancer_controller 
  that is to be deployed by helm.
  EOF
  type        = bool
  default     = true
}

variable "deploy_aws_load_balancer_controller_via_helm_provider" {
  description = "AWS Load Balancer Controller via Helm provider."
  type        = bool
  default     = false
}

variable "aws_load_balancer_controller_service_account_name" {
  description = "The name of AWS Load Balancer Controller's service account resource"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID to use for accessing your applications."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "The Route 53 Hosted Zone name to use for accessing your applications."
  type        = string
  default     = ""
}