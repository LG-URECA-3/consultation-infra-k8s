data "aws_ami" "data" {
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
  data_ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.data[0].id
}

resource "aws_instance" "elasticsearch" {
  ami                    = var.es_ami_id != null ? var.es_ami_id : local.data_ami_id
  instance_type          = var.es_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.app_instance_profile_name

  key_name = var.key_name

  tags = {
    Name = "${var.project_name}-elasticsearch"
    Role = "elasticsearch"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e
    # Packer 이미지와 동일 경로: /opt/docker-services/es, /opt/docker-data/es/data
    chown -R 1000:1000 /opt/docker-data/es/data
    cd /opt/docker-services/es && docker compose up -d
  EOT
}

resource "aws_instance" "kafka" {
  ami                    = var.kafka_ami_id != null ? var.kafka_ami_id : local.data_ami_id
  instance_type          = var.data_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.app_instance_profile_name

  key_name = var.key_name

  tags = {
    Name = "${var.project_name}-kafka"
    Role = "kafka"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e
    # Kafka docker-compose용 .env 생성 (packer/kafka/docker-compose.yml 참고)
    KAFKA_DIR="/opt/docker-services/kafka"
    mkdir -p "$KAFKA_DIR"
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
    echo "PRIVATE_IP=$PRIVATE_IP" > "$KAFKA_DIR/.env"
    cd "$KAFKA_DIR" && docker compose up -d
  EOT
}

resource "aws_instance" "redis" {
  ami                    = var.redis_ami_id != null ? var.redis_ami_id : local.data_ami_id
  instance_type          = var.data_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.db_sg_id]
  iam_instance_profile   = var.app_instance_profile_name

  key_name = var.key_name

  tags = {
    Name = "${var.project_name}-redis"
    Role = "redis"
  }

  user_data = <<-EOT
    #!/bin/bash
    set -e

    # 1. 작업 디렉토리 생성 및 권한 설정
    mkdir -p /opt/docker-services/redis
    mkdir -p /opt/docker-data/redis/data
    chmod 777 /opt/docker-data/redis/data

    # 2. SSM Parameter Store에서 비밀번호 가져오기
    # '/consultation/redis/password'는 실제 SSM에 저장된 경로로 변경하세요.
    SSM_PARAM_NAME="/config/consultation-service/redis_password"

    # 파라미터 값 가져오기 (SecureString인 경우 --with-decryption 옵션 필요)
    REDIS_PASSWORD=$(aws ssm get-parameter --name "$SSM_PARAM_NAME" --with-decryption --query "Parameter.Value" --output text --region ap-northeast-2)

    # 3. .env 파일 생성
    echo "REDIS_PASSWORD=$REDIS_PASSWORD" > /opt/docker-services/redis/.env

    # 4. Redis 컨테이너 실행
    cd /opt/docker-services/redis && docker compose up -d
  EOT
}

resource "aws_lb_target_group_attachment" "redis" {
  target_group_arn = var.redis_target_group_arn
  target_id        = aws_instance.redis.id
  port             = 6379
}

resource "aws_lb_target_group_attachment" "kafka" {
  target_group_arn = var.kafka_target_group_arn
  target_id        = aws_instance.kafka.id
  port             = 9092
}

resource "aws_lb_target_group_attachment" "elasticsearch" {
  target_group_arn = var.es_target_group_arn
  target_id        = aws_instance.elasticsearch.id
  port             = 9200
}

