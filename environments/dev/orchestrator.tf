terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================================
# Data Sources: 기존 공유 인프라 참조 (network-topology.md)
# ============================================================================

data "aws_ecs_cluster" "shared" {
  cluster_name = "mcp-agents-staging-cluster"
}

data "aws_lb" "shared" {
  name = "mcp-agents-staging-alb"
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/ecs/rorr-mcp-orchestrator"
  retention_in_days = 7

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
    Service     = "mcp-orchestrator"
  }
}

# ============================================================================
# IAM: Execution Role (ECR pull, CloudWatch logs)
# ============================================================================

resource "aws_iam_role" "execution" {
  name = "rorr-mcp-orchestrator-execution"

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

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_iam_role_policy_attachment" "execution_policy" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ============================================================================
# IAM: Task Role (Bedrock InvokeModel)
# ============================================================================

resource "aws_iam_role" "task" {
  name = "rorr-mcp-orchestrator-task"

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

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_iam_role_policy" "task_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          # Claude Haiku 4.5
          "arn:aws:bedrock:us-east-1:239460481239:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0",
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
          # Claude Opus 4.5
          "arn:aws:bedrock:us-east-1:239460481239:inference-profile/us.anthropic.claude-opus-4-5-20251101-v1:0",
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-opus-4-5-20251101-v1:0"
        ]
      }
    ]
  })
}

# ============================================================================
# ECS Task Definition
# ============================================================================

resource "aws_ecs_task_definition" "orchestrator" {
  family                   = "rorr-mcp-orchestrator-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode(
    [
      {
        name      = "rorr-mcp-orchestrator"
        image     = "239460481239.dkr.ecr.us-east-1.amazonaws.com/rorr-orchestrator:latest"
        essential = true
        portMappings = [
          {
            containerPort = 4000
            hostPort      = 4000
            protocol      = "tcp"
          }
        ]
        environment = [
          {
            name  = "PORT"
            value = "4000"
          },
          {
            name  = "LLM_PROVIDER"
            value = "bedrock"
          },
          {
            name  = "AWS_REGION"
            value = "us-east-1"
          },
          {
            name  = "LLM_MODEL"
            value = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
          },
          {
            name  = "MCP_INFRA_URL"
            value = "http://${data.aws_lb.shared.dns_name}:5010/mcp"
          },
          {
            name  = "DEFAULT_USER_ID"
            value = "woody@rorr.club"
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.orchestrator.name
            "awslogs-region"        = "us-east-1"
            "awslogs-stream-prefix" = "ecs"
          }
        }
      }
    ]
  )

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# ============================================================================
# ALB Target Group
# ============================================================================

resource "aws_lb_target_group" "orchestrator" {
  name        = "rorr-mcp-orchestrator-tg"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = "vpc-0e4611af2c26c7223"
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/health"
    port                = "4000"
    matcher             = "200"
  }

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# ============================================================================
# ALB Listener (data source 사용)
# ============================================================================

resource "aws_lb_listener" "orchestrator" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = "4000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.orchestrator.arn
  }

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# ============================================================================
# ECS Service
# ============================================================================

resource "aws_ecs_service" "orchestrator" {
  name            = "rorr-mcp-orchestrator-service"
  cluster         = data.aws_ecs_cluster.shared.id
  task_definition = aws_ecs_task_definition.orchestrator.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-02b19e578de089a89", "subnet-011389a22f856c694"]
    security_groups  = ["sg-082696c1f710d394d"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.orchestrator.arn
    container_name   = "rorr-mcp-orchestrator"
    container_port   = 4000
  }

  depends_on = [
    aws_lb_listener.orchestrator,
    aws_iam_role_policy.task_bedrock
  ]

  tags = {
    Environment = "dev"
    Team        = "infra"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}
