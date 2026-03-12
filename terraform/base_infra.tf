// Base VPC, Security Groups, ALB, NLB (README §2)
// This root module creates all base infrastructure and exposes locals
// (vpc_id, private_subnet_ids, alb_sg_id, db_sg_id, etc.) for other files.

module "network" {
  source = "./modules/network"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  vpc_cidr     = var.vpc_cidr
}

module "lb" {
  source = "./modules/lb"

  project_name               = var.project_name
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  mysql_listener_use_replica = var.mysql_listener_use_replica
}

// Locals used by other root-level resources (eks.tf, security.tf, karpenter.tf, etc.)
locals {
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  public_subnet_ids  = module.network.public_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  db_sg_id           = module.security.db_sg_id
  bastion_sg_id      = module.security.bastion_sg_id
}

// Optional Bastion host in public subnet
data "aws_ami" "bastion" {
  count       = var.create_bastion ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "bastion" {
  count                = var.create_bastion ? 1 : 0
  ami                  = var.bastion_ami_id != null ? var.bastion_ami_id : data.aws_ami.bastion[0].id
  instance_type        = "t4g.small"
  subnet_id            = local.public_subnet_ids[0]
  vpc_security_group_ids = [local.bastion_sg_id]
  key_name             = var.ssh_key_name

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

