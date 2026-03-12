output "redis_private_ip" {
  description = "Private IP of Redis instance"
  value       = aws_instance.redis.private_ip
}

output "kafka_private_ip" {
  description = "Private IP of Kafka instance"
  value       = aws_instance.kafka.private_ip
}

output "elasticsearch_private_ip" {
  description = "Private IP of Elasticsearch instance"
  value       = aws_instance.elasticsearch.private_ip
}

