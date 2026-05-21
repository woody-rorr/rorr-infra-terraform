locals {
  test_service_name   = "dev-test"
  test_container_name = "dev-test"
  test_container_port = 8888

  test_tags = {
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
    Service     = "test"
  }
}

data "aws_security_group" "shared_alb" {
  vpc_id = data.aws_vpc.shared.id

  filter {
    name   = "group-name"
    values = ["mcp-agents-staging-alb-sg"]
  }
}

resource "aws_security_group" "test_ecs_task" {
  name        = "dev-test-ecs-sg"
  description = "ECS task SG for dev-test Fargate service"
  vpc_id      = data.aws_vpc.shared.id

  ingress {
    description     = "Allow shared ALB to reach container port 8888"
    from_port       = local.test_container_port
    to_port         = local.test_container_port
    protocol        = "tcp"
    security_groups = [data.aws_security_group.shared_alb.id]
  }

  egress {
    description = "Allow all outbound for ECR pull, CloudWatch Logs and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.test_tags, { Name = "dev-test-ecs-sg" })
}

resource "aws_lb_target_group" "test" {
  name        = "dev-test-tg"
  port        = local.test_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.shared.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.test_tags, { Name = "dev-test-tg" })
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = local.test_container_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

resource "aws_ecs_service" "test" {
  name            = "dev-test-service"
  cluster         = data.aws_ecs_cluster.shared.arn
  task_definition = "dev-test"
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.test_ecs_task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test.arn
    container_name   = local.test_container_name
    container_port   = local.test_container_port
  }

  depends_on = [aws_lb_listener.test]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = merge(local.test_tags, { Name = "dev-test-service" })
}
