# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "rorr_mcp_orchestrator" {
  name              = "/ecs/rorr-mcp-orchestrator"
  retention_in_days = 7

  tags = {
    Name = "rorr-mcp-orchestrator-logs"
  }
}

# IAM Execution Role
resource "aws_iam_role" "rorr_mcp_orchestrator_execution" {
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
}

resource "aws_iam_role_policy_attachment" "rorr_mcp_orchestrator_execution_policy" {
  role       = aws_iam_role.rorr_mcp_orchestrator_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Task Role with Bedrock permissions
resource "aws_iam_role" "rorr_mcp_orchestrator_task" {
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
}

resource "aws_iam_role_policy" "rorr_mcp_orchestrator_bedrock" {
  name = "rorr-mcp-orchestrator-bedrock"
  role = aws_iam_role.rorr_mcp_orchestrator_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:bedrock:us-east-1:239460481239:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0",
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"
        ]
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "rorr_mcp_orchestrator" {
  family                   = "rorr-mcp-orchestrator-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.rorr_mcp_orchestrator_execution.arn
  task_role_arn            = aws_iam_role.rorr_mcp_orchestrator_task.arn

  container_definitions = jsonencode([
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
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.rorr_mcp_orchestrator.name
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
          value = "http://mcp-agents-staging-alb-249976027.us-east-1.elb.amazonaws.com:5010/mcp"
        },
        {
          name  = "DEFAULT_USER_ID"
          value = "woody@rorr.club"
        }
      ]
    }
  ])
}

# ALB Target Group
resource "aws_lb_target_group" "rorr_mcp_orchestrator" {
  name        = "rorr-mcp-orchestrator-tg"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = "vpc-0e4611af2c26c7223"
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "rorr-mcp-orchestrator-tg"
  }
}

# ALB Listener for port 4000
resource "aws_lb_listener" "rorr_mcp_orchestrator" {
  load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:239460481239:loadbalancer/app/mcp-agents-staging-alb/249976027"
  port              = "4000"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rorr_mcp_orchestrator.arn
  }
}

# ECS Service
resource "aws_ecs_service" "rorr_mcp_orchestrator" {
  name            = "rorr-mcp-orchestrator-service"
  cluster         = "arn:aws:ecs:us-east-1:239460481239:cluster/mcp-agents-staging-cluster"
  task_definition = aws_ecs_task_definition.rorr_mcp_orchestrator.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = ["subnet-02b19e578de089a89", "subnet-011389a22f856c694"]
    security_groups  = ["sg-082696c1f710d394d"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.rorr_mcp_orchestrator.arn
    container_name   = "rorr-mcp-orchestrator"
    container_port   = 4000
  }

  depends_on = [aws_lb_listener.rorr_mcp_orchestrator]

  tags = {
    Name = "rorr-mcp-orchestrator-service"
  }
}
