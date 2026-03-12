# ------------------------------------------------------------------------------
# EKS Node Security Group (eks-node-sg)
# ------------------------------------------------------------------------------
resource "aws_security_group" "eks_node" {
  name        = "${var.cluster_name}-eks-node-sg"
  description = "Security group for EKS worker nodes (system + Karpenter-provisioned)"
  vpc_id      = local.vpc_id

  # ALB -> Pod/Node (target type ip: traffic to pod IPs on node)
  ingress {
    description     = "API from ALB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [local.alb_sg_id]
  }

  ingress {
    description     = "Admin from ALB"
    from_port       = 8082
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [local.alb_sg_id]
  }

  ingress {
    description     = "FastAPI from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [local.alb_sg_id]
  }

  # EKS control plane to nodes (node registration, kubelet)
  ingress {
    description = "EKS control plane to node (443)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  ingress {
    description = "EKS control plane to kubelet (10250)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  # AWS Load Balancer Controller webhook (admission; API server / pods -> controller:9443)
  ingress {
    description     = "AWS LB Controller webhook (9443)"
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    cidr_blocks     = [local.vpc_cidr]
  }

  # Node-to-node (optional, for same-SG traffic)
  ingress {
    description = "Node to node"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-eks-node-sg"
    # Karpenter EC2NodeClass securityGroupSelector
    "karpenter.sh/discovery" = var.cluster_name
  }
}

# ------------------------------------------------------------------------------
# Allow worker nodes (eks-node-sg) to reach EKS control plane (cluster security group) on 443
# Kubernetes API endpoint is fronted by the cluster security group, which by default
# may not explicitly allow node SG traffic. Ensure explicit SG-to-SG rule.
# ------------------------------------------------------------------------------
resource "aws_security_group_rule" "cluster_api_from_eks_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.eks_node.id
  description              = "Allow EKS worker nodes to reach Kubernetes API (443)"
}

# ------------------------------------------------------------------------------
# Allow EKS nodes (eks-node-sg) to access DB layer (db_sg)
# ------------------------------------------------------------------------------
resource "aws_security_group_rule" "db_from_eks_node_mysql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = aws_security_group.eks_node.id
  description              = "MySQL from EKS nodes"
}

resource "aws_security_group_rule" "db_from_eks_node_redis" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = aws_security_group.eks_node.id
  description              = "Redis from EKS nodes"
}

resource "aws_security_group_rule" "db_from_eks_node_kafka" {
  type                     = "ingress"
  from_port                = 9092
  to_port                  = 9092
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = aws_security_group.eks_node.id
  description              = "Kafka from EKS nodes"
}

resource "aws_security_group_rule" "db_from_eks_node_es" {
  type                     = "ingress"
  from_port                = 9200
  to_port                  = 9200
  protocol                 = "tcp"
  security_group_id        = local.db_sg_id
  source_security_group_id = aws_security_group.eks_node.id
  description              = "Elasticsearch from EKS nodes"
}
