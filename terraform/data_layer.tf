// DB / Data layer (MySQL, Redis, Kafka, Elasticsearch) EC2 instances + NLB attachments
// Replicates the consultation-infra modules/compute-db and compute-data behavior,
// but runs fully inside this repo using base_infra outputs.

module "compute_db" {
  source = "./modules/compute-db"

  project_name                 = var.project_name
  ami_id                       = var.ami_id
  mysql_primary_ami_id         = var.mysql_primary_ami_id
  mysql_replica_ami_id         = var.mysql_replica_ami_id
  db_instance_type             = var.db_instance_type
  private_subnet_ids           = local.private_subnet_ids
  db_sg_id                     = local.db_sg_id
  app_instance_profile_name    = aws_iam_instance_profile.data_ec2.name
  mysql_primary_target_group_arn  = module.lb.mysql_primary_target_group_arn
  mysql_replica_target_group_arn  = module.lb.mysql_replica_target_group_arn
  enable_mysql_replica         = var.enable_mysql_replica
  key_name                     = var.ssh_key_name
}

module "compute_data" {
  source = "./modules/compute-data"

  project_name              = var.project_name
  ami_id                    = var.ami_id
  es_ami_id                 = var.es_ami_id
  kafka_ami_id              = var.kafka_ami_id
  redis_ami_id              = var.redis_ami_id
  es_instance_type          = var.es_instance_type
  data_instance_type        = var.data_instance_type
  private_subnet_ids        = local.private_subnet_ids
  db_sg_id                  = local.db_sg_id
  app_instance_profile_name = aws_iam_instance_profile.data_ec2.name
  redis_target_group_arn    = module.lb.redis_target_group_arn
  kafka_target_group_arn    = module.lb.kafka_target_group_arn
  es_target_group_arn       = module.lb.es_target_group_arn
  key_name                  = var.ssh_key_name
}

