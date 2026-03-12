data "aws_ami" "db" {
  count       = var.ami_id == null ? 1 : 0
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

locals {
  db_ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.db[0].id
}

resource "aws_instance" "mysql_master" {
  ami                    = var.mysql_primary_ami_id != null ? var.mysql_primary_ami_id : local.db_ami_id
  instance_type          = var.db_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.app_instance_profile_name

  key_name = var.key_name

  tags = {
    Name = "${var.project_name}-mysql-master"
    Role = "mysql-master"
  }

  user_data = <<-EOT
    #!/bin/bash
    # 0. 필수 설정
    set -e

    # 1. 작업 디렉토리 및 데이터 저장소 생성
    mkdir -p /opt/docker-services/mysql
    mkdir -p /opt/docker-data/mysql/data
    mkdir -p /opt/docker-data/mysql/conf.d

    # 2. SSM Parameter Store에서 정보 가져오기
    # 각 파라미터 경로는 실제 등록하신 경로로 수정하세요.
    SSM_ROOT_PASS="/config/consultation-service/db_root_password"
    SSM_DB_USER="/config/consultation-service/db_user"
    SSM_DB_PASS="/config/consultation-service/db_password"

    MYSQL_ROOT_PASSWORD=$(aws ssm get-parameter --name "$SSM_ROOT_PASS" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)
    MYSQL_USER=$(aws ssm get-parameter --name "$SSM_DB_USER" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)
    MYSQL_PASSWORD=$(aws ssm get-parameter --name "$SSM_DB_PASS" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)

    # 3. .env 파일 생성 (도커 컴포즈 주입용, 들여쓰기 없이 표준 .env 형식)
    echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" > /opt/docker-services/mysql/.env
    echo "MYSQL_USER=$MYSQL_USER" >> /opt/docker-services/mysql/.env
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> /opt/docker-services/mysql/.env

    # 4. 권한 설정 (MySQL 컨테이너는 UID 999 사용)
    chown -R 999:999 /opt/docker-data/mysql/data
    chmod 700 /opt/docker-data/mysql/data

    # 5. 컨테이너 구동 (이미지는 AMI에 포함되어 있음 → pull 불필요)
    cd /opt/docker-services/mysql && docker compose up -d
  EOT
}

resource "aws_instance" "mysql_slave" {
  count                   = var.enable_mysql_replica ? 1 : 0
  ami                    = var.mysql_replica_ami_id != null ? var.mysql_replica_ami_id : local.db_ami_id
  instance_type          = var.db_instance_type
  subnet_id              = var.private_subnet_ids[1]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.app_instance_profile_name

  key_name = var.key_name

  tags = {
    Name = "${var.project_name}-mysql-slave"
    Role = "mysql-slave"
  }

  user_data = <<-EOT
    #!/bin/bash
    # 0. 필수 설정
    set -e

    # 1. 작업 디렉토리 및 데이터 저장소 생성
    mkdir -p /opt/docker-services/mysql
    mkdir -p /opt/docker-data/mysql/data
    mkdir -p /opt/docker-data/mysql/conf.d

    # 2. SSM Parameter Store에서 정보 가져오기
    # 각 파라미터 경로는 실제 등록하신 경로로 수정하세요.
    SSM_ROOT_PASS="/config/consultation-service/db_root_password"
    SSM_DB_USER="/config/consultation-service/db_user"
    SSM_DB_PASS="/config/consultation-service/db_password"

    MYSQL_ROOT_PASSWORD=$(aws ssm get-parameter --name "$SSM_ROOT_PASS" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)
    MYSQL_USER=$(aws ssm get-parameter --name "$SSM_DB_USER" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)
    MYSQL_PASSWORD=$(aws ssm get-parameter --name "$SSM_DB_PASS" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)

    # 3. .env 파일 생성 (도커 컴포즈 주입용, 들여쓰기 없이 표준 .env 형식)
    echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" > /opt/docker-services/mysql/.env
    echo "MYSQL_USER=$MYSQL_USER" >> /opt/docker-services/mysql/.env
    echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> /opt/docker-services/mysql/.env

    # 4. 권한 설정 (MySQL 컨테이너는 UID 999 사용)
    chown -R 999:999 /opt/docker-data/mysql/data
    chmod 700 /opt/docker-data/mysql/data

    # 5. 컨테이너 구동 (이미지는 AMI에 포함되어 있음 → pull 불필요)
    cd /opt/docker-services/mysql && docker compose up -d
  EOT
}

resource "aws_lb_target_group_attachment" "mysql_master" {
  target_group_arn = var.mysql_primary_target_group_arn
  target_id        = aws_instance.mysql_master.id
  port             = 3306
}

resource "aws_lb_target_group_attachment" "mysql_slave" {
  count            = var.enable_mysql_replica ? 1 : 0
  target_group_arn = var.mysql_replica_target_group_arn
  target_id        = aws_instance.mysql_slave[0].id
  port             = 3306
}

