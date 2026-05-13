# Data sources - 기존 인프라 재사용
data "aws_ecs_cluster" "shared" {
  name = "mcp-agents-staging-cluster"
}

data "aws_lb" "shared" {
  name = "mcp-agents-staging-alb"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/ecs/rorr-mcp-orchestrator"
  retention_in_days = 7

  tags = {
    Name        = "rorr-mcp-orchestrator-logs"
    Environment = "dev"
  }
}

# IAM Execution Role
resource "aws_iam_role" "orchestrator_execution" {
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
    Name        = "rorr-mcp-orchestrator-execution"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "orchestrator_execution" {
  role       = aws_iam_role.orchestrator_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Task Role (Bedrock 권한)
resource "aws_iam_role" "orchestrator_task" {
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
    Name        = "rorr-mcp-orchestrator-task"
    Environment = "dev"
  }
}

# Bedrock invoke 권한
resource "aws_iam_role_policy" "orchestrator_bedrock" {
  name = "rorr-mcp-orchestrator-bedrock-invoke"
  role = aws_iam_role.orchestrator_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:us-east-1::inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:us-east-1:*:foundation-model/anthropic.claude-haiku-4-5-20251001-v1"
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "orchestrator" {
  family                   = "rorr-mcp-orchestrator-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.orchestrator_execution.arn
  task_role_arn            = aws_iam_role.orchestrator_task.arn

  container_definitions = jsonencode([
    {
      name      = "rorr-mcp-orchestrator"
      image     = "239460481239.dkr.ecr.us-east-1.amazonaws.com/rorr-orchestrator:latest"
      portMappings = [
        {
          containerPort = 4000
          hostPort      = 4000
          protocol      = "tcp"
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
    }
  ])

  tags = {
    Name        = "rorr-mcp-orchestrator-task"
    Environment = "dev"
  }
}

# Target Group
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
    matcher             = "200"
  }

  tags = {
    Name        = "rorr-mcp-orchestrator-tg"
    Environment = "dev"
  }
}

# ALB Listener
resource "aws_lb_listener" "orchestrator" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = "4000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.orchestrator.arn
  }

  tags = {
    Name        = "rorr-mcp-orchestrator-listener"
    Environment = "dev"
  }
}

# ECS Service
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
    aws_lb_listener.orchestrator
  ]

  tags = {
    Name        = "rorr-mcp-orchestrator-service"
    Environment = "dev"
  }
}

# Outputs
output "ecs_service_name" {
  description = "ECS Service 이름"
  value       = aws_ecs_service.orchestrator.name
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.orchestrator.arn
}

output "orchestrator_endpoint" {
  description = "Orchestrator 엔드포인트 URL"
  value       = "http://${data.aws_lb.shared.dns_name}:4000"
}
