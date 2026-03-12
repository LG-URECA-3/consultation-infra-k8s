# ------------------------------------------------------------------------------
# SSM Parameter Store (consultation-infra 참고)
# 애플리케이션 및 데이터 계층 EC2 user_data에서 참조
# 민감 정보(db_root_password, db_user, db_password, redis_password)는 변수로 주입
# ------------------------------------------------------------------------------
locals {
  ssm_prefix = "/config/consultation-service/prod"
}

# ------------------------------------------------------------------------------
# DB URL (NLB DNS 기반)
# application-*.yml: DB.URL
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "db_url" {
  name  = "${local.ssm_prefix}/db_url"
  type  = "String"
  value = "jdbc:mysql://${module.lb.nlb_dns_name}:3306/consultation_db?useSSL=false&allowPublicKeyRetrieval=true&characterEncoding=UTF-8&serverTimezone=Asia/Seoul"
}

resource "aws_ssm_parameter" "db_host" {
  name  = "${local.ssm_prefix}/db_host"
  type  = "String"
  value = module.lb.nlb_dns_name
}

# ------------------------------------------------------------------------------
# Redis (NLB DNS + 고정 포트)
# application-*.yml: REDIS.HOST, REDIS.PORT
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "redis_host" {
  name  = "${local.ssm_prefix}/redis_host"
  type  = "String"
  value = module.lb.nlb_dns_name
}

resource "aws_ssm_parameter" "redis_port" {
  name  = "${local.ssm_prefix}/redis_port"
  type  = "String"
  value = "6379"
}

# ------------------------------------------------------------------------------
# Kafka (NLB DNS + 9092)
# application-*.yml: KAFKA.BOOTSTRAP_SERVERS
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "kafka_bootstrap_servers" {
  name  = "${local.ssm_prefix}/kafka_bootstrap_servers"
  type  = "String"
  value = "${module.lb.nlb_dns_name}:9092"
}

resource "aws_ssm_parameter" "kafka_consumer_group_id" {
  name  = "${local.ssm_prefix}/kafka_consumer_group_id"
  type  = "String"
  value = "consultation-consumer"
}

resource "aws_ssm_parameter" "kafka_auto_offset_reset" {
  name  = "${local.ssm_prefix}/kafka_auto_offset_reset"
  type  = "String"
  value = "latest"
}

# ------------------------------------------------------------------------------
# Elasticsearch URI (Admin 헬스체크용)
# admin-module: spring.elasticsearch.uris
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "elasticsearch_uris" {
  name  = "${local.ssm_prefix}/elasticsearch_uris"
  type  = "String"
  value = "http://${module.lb.nlb_dns_name}:9200"
}

# ------------------------------------------------------------------------------
# ALB DNS (Ingress ALB, 외부에서 앱 접근 시 활용)
# terraform apply 후 kubectl get ingress -n consultation-prod 로 확인 가능
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "alb_dns_name" {
  count  = var.ssm_alb_dns_name != null ? 1 : 0
  name   = "${local.ssm_prefix}/alb_dns_name"
  type   = "String"
  value  = var.ssm_alb_dns_name
}

# ------------------------------------------------------------------------------
# 서버 포트 (API / ADMIN / WORKER / FASTAPI)
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "api_port" {
  name  = "${local.ssm_prefix}/server_port_api"
  type  = "String"
  value = "8081"
}

resource "aws_ssm_parameter" "admin_port" {
  name  = "${local.ssm_prefix}/server_port_admin"
  type  = "String"
  value = "8082"
}

resource "aws_ssm_parameter" "worker_port" {
  name  = "${local.ssm_prefix}/server_port_worker"
  type  = "String"
  value = "8083"
}

resource "aws_ssm_parameter" "fastapi_port" {
  name  = "${local.ssm_prefix}/server_port_fastapi"
  type  = "String"
  value = "8000"
}

# ------------------------------------------------------------------------------
# 민감 정보 (SecureString) - tfvars 또는 -var로 주입
# 데이터 계층 EC2 user_data 및 애플리케이션에서 참조
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "db_root_password" {
  count       = var.ssm_db_root_password != null ? 1 : 0
  name        = "${local.ssm_prefix}/db_root_password"
  type        = "SecureString"
  value       = var.ssm_db_root_password
  description = "MySQL root password"
}

resource "aws_ssm_parameter" "db_user" {
  count       = var.ssm_db_user != null ? 1 : 0
  name        = "${local.ssm_prefix}/db_user"
  type        = "SecureString"
  value       = var.ssm_db_user
  description = "MySQL application user"
}

resource "aws_ssm_parameter" "db_password" {
  count       = var.ssm_db_password != null ? 1 : 0
  name        = "${local.ssm_prefix}/db_password"
  type        = "SecureString"
  value       = var.ssm_db_password
  description = "MySQL application password"
}

resource "aws_ssm_parameter" "redis_password" {
  count       = var.ssm_redis_password != null ? 1 : 0
  name        = "${local.ssm_prefix}/redis_password"
  type        = "SecureString"
  value       = var.ssm_redis_password
  description = "Redis password"
}
