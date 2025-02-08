locals {
  name         = "ingress"
  cluster_name = format("%s-%s", local.name, "eks-cluster")

  default_tags = {
    stack       = local.name
    terraform   = true
    description = "Test ingress on AWS EKS"
  }
}

module "vpc" {
  count              = var.create_vpc ? 1 : 0
  source             = "./modules/vpc"
  stack_name         = local.name
  vpc_cidr_block     = "10.1.0.0/16"
  create_nat_gateway = true # Fargate profile needs private subnet

  list_of_azs                = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  list_of_public_cidr_range  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
  list_of_private_cidr_range = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]

  default_tags = local.default_tags
  cluster_name = local.cluster_name
}

output "list_of_public_subnet_ids" {
  value = module.vpc[0].list_of_public_subnet_ids
}

output "list_of_private_subnet_ids" {
  value = module.vpc[0].list_of_private_subnet_ids
}