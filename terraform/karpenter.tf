# ------------------------------------------------------------------------------
# Subnet tags for Karpenter discovery (EC2NodeClass subnetSelector)
# Two private subnets created/used by this module; add Karpenter discovery tag.
# Terraform needs static for_each keys, so we map indexes (0,1) -> subnet IDs.
# ------------------------------------------------------------------------------
resource "aws_ec2_tag" "private_subnet_karpenter" {
  for_each = {
    "0" = local.private_subnet_ids[0]
    "1" = local.private_subnet_ids[1]
  }

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
