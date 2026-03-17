# ------------------------------------------------------------------------------
# VPC Interface Endpoints for SSM Session Manager
# Allows instances in private subnets to register and accept SSM sessions without NAT.
# ------------------------------------------------------------------------------

resource "aws_security_group" "ssm_vpce" {
  name        = "${var.project_name}-ssm-vpce-sg"
  description = "Allow HTTPS from VPC to SSM VPC endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ssm-vpce-sg"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-vpce"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-vpce"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.ssm_vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-vpce"
  }
}
