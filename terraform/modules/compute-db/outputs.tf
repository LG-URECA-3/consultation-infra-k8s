output "mysql_master_private_ip" {
  description = "Private IP of MySQL Master instance"
  value       = aws_instance.mysql_master.private_ip
}

output "mysql_slave_private_ip" {
  description = "Private IP of MySQL Slave instance (null when enable_mysql_replica is false)"
  value       = var.enable_mysql_replica ? aws_instance.mysql_slave[0].private_ip : null
}

