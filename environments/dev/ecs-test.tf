data "aws_vpc" "mcp_agents_staging" {
  filter {
    name   = "tag:Name"
    values = ["mcp-agents-staging-vpc"]
  }
}

data "aws_subnets" "mcp_agents_staging_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.mcp_agents_staging.id]
  }
  filter {
    name   = "tag:Name"
    values = ["mcp-agents-staging-public-*"]
  }
}

data "aws_ecs_task_definition" "dev_test" {
  task_definition = "dev-test"
}

resource "aws_security_group" "dev_test_ecs" {
  name        = "dev-test-ecs-sg"
  description = "Security group for dev-test ECS service tasks"
  vpc_id      = data.aws_vpc.mcp_agents_staging.id

  ingress {
    description     = "Allow 8888 from shared ALB SG"
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = [data.aws_security_group.shared_alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "dev-test-ecs-sg"
    Environment = "dev"
    Team        = "rorr"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_lb_target_group" "dev_test" {
  name        = "dev-test-tg"
  port        = 8888
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.mcp_agents_staging.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Name        = "dev-test-tg"
    Environment = "dev"
    Team        = "rorr"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_lb_listener" "dev_test_8888" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 8888
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dev_test.arn
  }

  tags = {
    Name        = "dev-test-listener-8888"
    Environment = "dev"
    Team        = "rorr"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

resource "aws_ecs_service" "dev_test" {
  name            = "dev-test"
  cluster         = data.aws_ecs_cluster.shared.arn
  task_definition = data.aws_ecs_task_definition.dev_test.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.mcp_agents_staging_public.ids
    security_groups  = [aws_security_group.dev_test_ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dev_test.arn
    container_name   = "dev-test"
    container_port   = 8888
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.dev_test_8888]

  tags = {
    Name        = "dev-test"
    Environment = "dev"
    Team        = "rorr"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}
