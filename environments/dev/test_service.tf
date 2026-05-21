# dev-test ECS Fargate service on port 8888
# 공유 인프라 (VPC/ALB/Cluster/Subnets) 는 orchestrator.tf 에서 이미 선언된
# data source 들을 참조한다. 여기서는 재선언하지 않는다.

# 이미 존재하는 dev-test task definition 참조 (latest revision)
data "aws_ecs_task_definition" "test" {
  task_definition = "dev-test"
}

# dev-test 서비스 전용 ECS task SG
# 공유 ALB SG (sg-0ebd5a00d52cd3731) 에서만 8888 inbound 허용
resource "aws_security_group" "test_ecs" {
  name        = "dev-test-ecs-sg"
  description = "Security group for dev-test ECS service tasks"
  vpc_id      = data.aws_vpc.shared.id

  ingress {
    description     = "Allow 8888 from shared ALB SG"
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = ["sg-0ebd5a00d52cd3731"]
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
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# 공유 ALB SG 에 8888 inbound 룰 추가 (dev only, 0.0.0.0/0)
# 기존 SG 본체는 건드리지 않고 별도 룰 리소스로 추가
resource "aws_security_group_rule" "alb_test_ingress_8888" {
  type              = "ingress"
  from_port         = 8888
  to_port           = 8888
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "sg-0ebd5a00d52cd3731"
  description       = "Allow 8888 inbound for dev-test service"
}

# dev-test Target Group (Fargate awsvpc -> target_type=ip)
resource "aws_lb_target_group" "test" {
  name        = "dev-test-tg"
  port        = 8888
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.shared.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "dev-test-tg"
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# 공유 ALB 의 8888 포트에 신규 listener (forward -> test TG)
resource "aws_lb_listener" "test" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 8888
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }

  tags = {
    Name        = "dev-test-listener"
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# CloudWatch Log Group (task definition 이 이 이름을 가리킨다고 가정)
resource "aws_cloudwatch_log_group" "test" {
  name              = "/ecs/dev-test"
  retention_in_days = 7

  tags = {
    Name        = "/ecs/dev-test"
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# dev-test ECS Service
# 공유 인프라가 public subnet 만 제공하므로 assign_public_ip=true 로
# ECR pull 가능하게 한다 (보안은 task SG 가 ALB SG inbound 만 허용하여 통제)
resource "aws_ecs_service" "test" {
  name            = "dev-test"
  cluster         = data.aws_ecs_cluster.shared.arn
  task_definition = data.aws_ecs_task_definition.test.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.test_ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test.arn
    container_name   = "test" # TODO: 실제 task definition 의 container name 과 일치하는지 확인
    container_port   = 8888
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.test]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = {
    Name        = "dev-test"
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}
