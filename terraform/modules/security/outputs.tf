output "alb_sg_id" {
  description = "Security group ID for ALB (Ingress)"
  value       = aws_security_group.alb_sg.id
}

output "db_sg_id" {
  description = "Security group ID for DB/data layer EC2"
  value       = aws_security_group.db_sg.id
}

output "bastion_sg_id" {
  description = "Security group ID for Bastion host"
  value       = aws_security_group.bastion_sg.id
}
