# 【未検証！！！！】
# VPC Link統合モジュール
# ALB + ECS Fargate構成でのVPC Link統合（本番実装用）
#
# アーキテクチャ:
# API Gateway → VPC Link → ALB → Target Group → ECS Fargate (API Server 1, 2)
#
# ALBでパスベースルーティング:
# - /users/*  → API Server 1
# - /orders/* → API Server 2

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VPC構成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

# プライベートサブネット（マルチAZ）
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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ALB (Application Load Balancer)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  # VPC Link経由でのみアクセス可能
  ingress {
    description = "Allow HTTP from VPC Link"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-alb-sg"
    }
  )
}

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = true # プライベートALB（VPC内部のみ）
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id

  enable_deletion_protection = false # 開発用: 本番では true に変更

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-alb"
    }
  )
}

# デフォルトリスナー（80番ポート）
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # デフォルトアクション: 404 Not Found
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ message = "Not Found" })
      status_code  = "404"
    }
  }

  tags = var.tags
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ECS Cluster & Security Group
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  tags = var.tags
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  # ALBからのトラフィックのみ許可
  ingress {
    description     = "Allow traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-ecs-tasks-sg"
    }
  )
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API Server 1 (Users Service) - Target Group & ECS Service
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_lb_target_group" "api_server_1" {
  name        = "${var.name_prefix}-users-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate uses awsvpc network mode

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = merge(
    var.tags,
    {
      Name    = "${var.name_prefix}-users-tg"
      Service = "users"
    }
  )
}

# /users/* へのルーティングルール
resource "aws_lb_listener_rule" "users" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server_1.arn
  }

  condition {
    path_pattern {
      values = ["/users", "/users/*"]
    }
  }

  tags = merge(
    var.tags,
    {
      Service = "users"
    }
  )
}

# ECS Task Definition - API Server 1
resource "aws_ecs_task_definition" "api_server_1" {
  family                   = "${var.name_prefix}-users-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "users-api"
      image     = var.api_server_1_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SERVICE_NAME"
          value = "users"
        },
        {
          name  = "PORT"
          value = "8080"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api_server_1.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "users"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Service = "users"
    }
  )
}

# CloudWatch Log Group - API Server 1
resource "aws_cloudwatch_log_group" "api_server_1" {
  name              = "/ecs/${var.name_prefix}-users-service"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Service = "users"
    }
  )
}

# ECS Service - API Server 1
resource "aws_ecs_service" "api_server_1" {
  name            = "${var.name_prefix}-users-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_server_1.arn
  desired_count   = var.api_server_1_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_server_1.arn
    container_name   = "users-api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.main]

  tags = merge(
    var.tags,
    {
      Service = "users"
    }
  )
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# API Server 2 (Orders Service) - Target Group & ECS Service
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

resource "aws_lb_target_group" "api_server_2" {
  name        = "${var.name_prefix}-orders-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = merge(
    var.tags,
    {
      Name    = "${var.name_prefix}-orders-tg"
      Service = "orders"
    }
  )
}

# /orders/* へのルーティングルール
resource "aws_lb_listener_rule" "orders" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server_2.arn
  }

  condition {
    path_pattern {
      values = ["/orders", "/orders/*"]
    }
  }

  tags = merge(
    var.tags,
    {
      Service = "orders"
    }
  )
}

# ECS Task Definition - API Server 2
resource "aws_ecs_task_definition" "api_server_2" {
  family                   = "${var.name_prefix}-orders-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "orders-api"
      image     = var.api_server_2_image
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "SERVICE_NAME"
          value = "orders"
        },
        {
          name  = "PORT"
          value = "8080"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api_server_2.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "orders"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Service = "orders"
    }
  )
}

# CloudWatch Log Group - API Server 2
resource "aws_cloudwatch_log_group" "api_server_2" {
  name              = "/ecs/${var.name_prefix}-orders-service"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Service = "orders"
    }
  )
}

# ECS Service - API Server 2
resource "aws_ecs_service" "api_server_2" {
  name            = "${var.name_prefix}-orders-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_server_2.arn
  desired_count   = var.api_server_2_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_server_2.arn
    container_name   = "orders-api"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.main]

  tags = merge(
    var.tags,
    {
      Service = "orders"
    }
  )
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VPC Link (REST API用 - NLBが必要)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 注意: REST API (API Gateway v1) のVPC LinkはNLBのみサポート
# HTTP API (API Gateway v2) の場合はALBも使用可能

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

# NLB Target Group (ALBを指すように設定)
resource "aws_lb_target_group" "nlb_to_alb" {
  name        = "${var.name_prefix}-nlb-alb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "alb"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    protocol            = "HTTP"
    path                = "/health" # ALBのヘルスチェック用パス
    unhealthy_threshold = 2
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-nlb-alb-tg"
    }
  )
}

# NLBリスナー
resource "aws_lb_listener" "nlb" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_to_alb.arn
  }

  tags = var.tags
}

# ALBをNLBのターゲットとして登録
resource "aws_lb_target_group_attachment" "nlb_to_alb" {
  target_group_arn = aws_lb_target_group.nlb_to_alb.arn
  target_id        = aws_lb.main.arn
  port             = 80
}

# VPC Link
resource "aws_api_gateway_vpc_link" "main" {
  name        = "${var.name_prefix}-vpc-link"
  description = "VPC Link for private ALB access"
  target_arns = [aws_lb.nlb.arn]

  tags = var.tags
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# IAM Roles for ECS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ECS Execution Role (ECRからイメージをpull、CloudWatch Logsに書き込み)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (タスク内のアプリケーションが使用)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# 必要に応じてタスクロールにポリシーを追加
# 例: DynamoDBアクセス、S3アクセスなど
