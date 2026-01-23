# LocalStack用 簡易VPC Link統合モジュール
# LocalStackの制限により、フルのECS/Fargate構成ではなく簡易版を提供

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-vpc"
    }
  )
}

# プライベートサブネット
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
    }
  )
}

# Network Load Balancer
resource "aws_lb" "nlb" {
  name               = "${var.name_prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-nlb"
    }
  )
}

# NLB Target Group
# LocalStackでは実際のターゲット（バックエンドサーバー）を指す
resource "aws_lb_target_group" "backend" {
  name        = "${var.name_prefix}-backend-tg"
  port        = var.backend_port
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    protocol            = "HTTP"
    path                = "/health"
    unhealthy_threshold = 2
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-backend-tg"
    }
  )
}

# NLBリスナー
resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.backend_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  tags = var.tags
}

# VPC Link (REST API用)
resource "aws_api_gateway_vpc_link" "main" {
  name        = "${var.name_prefix}-vpc-link"
  description = "VPC Link for LocalStack testing"
  target_arns = [aws_lb.nlb.arn]

  tags = var.tags
}

# ターゲット登録（バックエンドサーバーのIPアドレス）
# LocalStackではdocker-composeネットワーク内のIPを使用
resource "aws_lb_target_group_attachment" "backend" {
  count            = length(var.backend_ips)
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = var.backend_ips[count.index]
  port             = var.backend_port
}
