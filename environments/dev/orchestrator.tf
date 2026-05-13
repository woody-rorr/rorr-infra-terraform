# rorr-orchestrator ECS Fargate Service

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "rorr_orchestrator" {
  name              = "/ecs/rorr-orchestrator"
  retention_in_days = 7

  tags = {
    Name = "rorr-orchestrator-logs"
  }
}

# Task Execution Role
resource "aws_iam_role" "rorr_orchestrator_execution_role" {
  name = "rorr-orchestrator-execution"

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
}

resource "aws_iam_role_policy_attachment" "rorr_orchestrator_execution_policy" {
  role       = aws_iam_role.rorr_orchestrator_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (with Bedrock permissions)
resource "aws_iam_role" "rorr_orchestrator_task_role" {
  name = "rorr-orchestrator-task"

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
}

resource "aws_iam_role_policy" "rorr_orchestrator_bedrock_policy" {
  name = "rorr-orchestrator-bedrock"
  role = aws_iam_role.rorr_orchestrator_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:us-east-1::foundation-model/us.anthropic.claude-haiku-4-5-20251001-v1:0"
      }
    ]
  })
}

# Task Definition
resource "aws_ecs_task_definition" "rorr_orchestrator" {
  family                   = "rorr-orchestrator-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.rorr_orchestrator_execution_role.arn
  task_role_arn            = aws_iam_role.rorr_orchestrator_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "rorr-orchestrator"
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
          value = "http://mcp-agents-staging-alb-249976027.us-east-1.elb.amazonaws.com:5010/mcp"
        },
        {
          name  = "DEFAULT_USER_ID"
          value = "woody@rorr.club"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rorr_orchestrator.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "rorr-orchestrator-task"
  }
}

# Target Group
resource "aws_lb_target_group" "rorr_orchestrator" {
  name        = "rorr-orchestrator-tg"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.staging.id
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
    Name = "rorr-orchestrator-tg"
  }
}

# ALB Listener Rule
resource "aws_lb_listener" "rorr_orchestrator" {
  load_balancer_arn = data.aws_lb.staging.arn
  port              = 4000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rorr_orchestrator.arn
  }
}

# ECS Service
resource "aws_ecs_service" "rorr_orchestrator" {
  name            = "rorr-orchestrator-service"
  cluster         = data.aws_ecs_cluster.staging.id
  task_definition = aws_ecs_task_definition.rorr_orchestrator.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.rorr_orchestrator.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rorr_orchestrator.arn
    container_name   = "rorr-orchestrator"
    container_port   = 4000
  }

  depends_on = [
    aws_lb_listener.rorr_orchestrator,
    aws_iam_role_policy.rorr_orchestrator_bedrock_policy
  ]

  tags = {
    Name = "rorr-orchestrator-service"
  }
}

# Security Group
resource "aws_security_group" "rorr_orchestrator" {
  name   = "rorr-orchestrator-sg"
  vpc_id = data.aws_vpc.staging.id

  ingress {
    from_port   = 4000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rorr-orchestrator-sg"
  }
}

# Data sources
data "aws_vpc" "staging" {
  filter {
    name   = "tag:Name"
    values = ["staging"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.staging.id]
  }
}

data "aws_ecs_cluster" "staging" {
  name = "mcp-agents-staging-cluster"
}

data "aws_lb" "staging" {
  name = "mcp-agents-staging-alb"
}
