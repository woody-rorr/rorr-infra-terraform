# dev/test - ECS Task Definition + supporting resources
# 가정: environments/dev/ 하위에 provider "aws" 블록이 이미 존재함

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ECR 레포지토리는 사전 생성되어 있음 (data source로 조회 — 하드코딩 금지)
data "aws_ecr_repository" "test" {
  name = "test"
}

locals {
  service        = "test"
  environment    = "dev"
  name_prefix    = "${local.environment}-${local.service}"
  # 기존 ECS 서비스와 충돌 회피용 포트 (8888). 실제 사용 전 확인 필요.
  container_port = 8888

  common_tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "rorr"
    # Team 태그는 사용자 요청에 따라 의도적으로 생략 (테스트용)
  }
}

resource "aws_cloudwatch_log_group" "test" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
  tags              = local.common_tags
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "test_execution" {
  name               = "${local.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "test_execution_managed" {
  role       = aws_iam_role.test_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "test_task" {
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = local.common_tags
}

resource "aws_ecs_task_definition" "test" {
  family                   = "${local.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.test_execution.arn
  task_role_arn            = aws_iam_role.test_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = local.service
      image     = "${data.aws_ecr_repository.test.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.test.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

output "test_task_definition_arn" {
  value       = aws_ecs_task_definition.test.arn
  description = "ARN of the dev-test ECS task definition"
}

output "test_container_port" {
  value       = local.container_port
  description = "Container port exposed by the dev-test task"
}
