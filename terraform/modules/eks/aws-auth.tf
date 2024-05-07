module "aws-auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.8.5"

  manage_aws_auth_configmap = true

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::416170240696:user/liad"
      username = "liad"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::416170240696:user/omer"
      username = "omer"
      groups   = ["system:masters"]
    },
  ]
#  aws_auth_roles = [s
#    {
#      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/EKSAdmins-${module.eks.cluster_name}",
#      username = "eks-admin-${module.eks.cluster_name}",
#      groups   = ["system:masters"]
#    },
#    {
#      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/EKSDevelopers-${module.eks.cluster_name}",
#      username = "eks-dev-${module.eks.cluster_name}",
#      groups   = ["dev-group"]
#    }
#  ]
}
