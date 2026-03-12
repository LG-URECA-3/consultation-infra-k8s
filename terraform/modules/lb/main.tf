# ------------------------------------------------------------------------------
# Internal NLB for DB layer (MySQL, Redis, Kafka, ES)
# ALB is created by Kubernetes Ingress + AWS Load Balancer Controller (k8s_app.tf)
# ------------------------------------------------------------------------------
resource "aws_lb" "db_nlb" {
  name               = "${var.project_name}-db-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-nlb"
  }
}

resource "aws_lb_target_group" "mysql_primary_tg" {
  name        = "${var.project_name}-mysql-primary-tg"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "3306"
  }

  tags = {
    Name = "${var.project_name}-mysql-primary-tg"
  }
}

resource "aws_lb_target_group" "mysql_replica_tg" {
  name        = "${var.project_name}-mysql-replica-tg"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "3306"
  }

  tags = {
    Name = "${var.project_name}-mysql-replica-tg"
  }
}

resource "aws_lb_listener" "mysql" {
  load_balancer_arn = aws_lb.db_nlb.arn
  port              = "3306"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = var.mysql_listener_use_replica ? aws_lb_target_group.mysql_replica_tg.arn : aws_lb_target_group.mysql_primary_tg.arn
  }
}

resource "aws_lb_target_group" "redis_tg" {
  name        = "${var.project_name}-redis-tg"
  port        = 6379
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "6379"
  }

  tags = {
    Name = "${var.project_name}-redis-tg"
  }
}

resource "aws_lb_target_group" "kafka_tg" {
  name        = "${var.project_name}-kafka-tg"
  port        = 9092
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "9092"
  }

  tags = {
    Name = "${var.project_name}-kafka-tg"
  }
}

resource "aws_lb_target_group" "es_tg" {
  name        = "${var.project_name}-es-tg"
  port        = 9200
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = "9200"
  }

  tags = {
    Name = "${var.project_name}-es-tg"
  }
}

resource "aws_lb_listener" "redis" {
  load_balancer_arn = aws_lb.db_nlb.arn
  port              = "6379"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.redis_tg.arn
  }
}

resource "aws_lb_listener" "kafka" {
  load_balancer_arn = aws_lb.db_nlb.arn
  port              = "9092"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_tg.arn
  }
}

resource "aws_lb_listener" "es" {
  load_balancer_arn = aws_lb.db_nlb.arn
  port              = "9200"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.es_tg.arn
  }
}
