output "nlb_dns_name" {
  description = "Internal NLB DNS name (MySQL/Redis/Kafka/ES)"
  value       = aws_lb.db_nlb.dns_name
}

output "mysql_primary_target_group_arn" {
  description = "Target group ARN for MySQL primary"
  value       = aws_lb_target_group.mysql_primary_tg.arn
}

output "mysql_replica_target_group_arn" {
  description = "Target group ARN for MySQL replica"
  value       = aws_lb_target_group.mysql_replica_tg.arn
}

output "redis_target_group_arn" {
  description = "Target group ARN for Redis"
  value       = aws_lb_target_group.redis_tg.arn
}

output "kafka_target_group_arn" {
  description = "Target group ARN for Kafka"
  value       = aws_lb_target_group.kafka_tg.arn
}

output "es_target_group_arn" {
  description = "Target group ARN for Elasticsearch"
  value       = aws_lb_target_group.es_tg.arn
}
