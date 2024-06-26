# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "default" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "default" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}
