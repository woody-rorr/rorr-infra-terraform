terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# =========================================================
# Variables
# =========================================================
variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "dev"
}

variable "service_name" {
  type        = string
  description = "Service short name (used in resource naming)"
  default     = "test"
}

variable "container_name" {
  type        = string
  description = "Container name as defined in the existing dev-test task definition (MUST match for ALB target binding)"
  default     = "test"
}

variable "container_port" {
  type        = number
  description = "Container port exposed by the test service"
  default     = 8888
}

variable "desired_count" {
  type        = number
  description = "Desired ECS task count (dev keeps it at 1)"
  default     = 1
}

variable "task_definition_family" {
  type        = string
  description = "Existing ECS task definition family (already created by user)"
  default     = "dev-test"
}

variable "alb_listener_port" {
  type        = number
  description = "Existing listener port on the shared ALB to attach the rule to"
  default     = 80
}

variable "alb_listener_rule_priority" {
  type        = number
  description = "ALB listener rule priority - must be unique across existing rules"
  default     = 500
}

variable "alb_host_header" {
  type        = string
  description = "Host header used to route traffic to this test service - adjust to actual hostname"
  default     = "dev-test.internal.rorr"
}

variable "health_check_path" {
  type        = string
  description = "HTTP health check path exposed by the container"
  default     = "/health"
}

# =========================================================
# Locals
# =========================================================
locals {
  name = "${var.environment}-${var.service_name}"

  common_tags = {
    Environment = var.environment
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "rorr"
  }
}

# =========================================================
# Shared infra data sources (NEVER hardcode ARNs)
# =========================================================
data "aws_vpc" "shared" {
  id = "vpc-0e4611af2c26c7223"
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "tag:Name"
    values = ["mcp-agents-staging-public-*"]
  }
}

data "aws_ecs_cluster" "shared" {
  cluster_name = "mcp-agents-staging-cluster"
}

data "aws_lb" "shared" {
  name = "mcp-agents-staging-alb"
}

data "aws_lb_listener" "shared" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = var.alb_listener_port
}

data "aws_security_group" "alb" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "group-name"
    values = ["mcp-agents-staging-alb-sg"]
  }
}

data "aws_ecs_task_definition" "test" {
  task_definition = var.task_definition_family
}

# =========================================================
# Security group for the ECS task ENIs
# Only the shared ALB SG may reach container_port (8888).
# =========================================================
resource "aws_security_group" "test_ecs" {
  name        = "${local.name}-ecs-sg"
  description = "SG for ${local.name} ECS Fargate tasks"
  vpc_id      = data.aws_vpc.shared.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-ecs-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "test_from_alb" {
  security_group_id            = aws_security_group.test_ecs.id
  description                  = "Allow shared ALB to reach test container on ${var.container_port}"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = data.aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "test_egress_all" {
  security_group_id = aws_security_group.test_ecs.id
  description       = "Allow all outbound (image pull, AWS APIs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# =========================================================
# ALB Target Group + Listener Rule (host-based routing,
# unique priority to avoid clashing with other services)
# =========================================================
resource "aws_lb_target_group" "test" {
  name        = "${local.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.shared.id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = var.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    Name = "${local.name}-tg"
  })
}

resource "aws_lb_listener_rule" "test" {
  listener_arn = data.aws_lb_listener.shared.arn
  priority     = var.alb_listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }

  condition {
    host_header {
      values = [var.alb_host_header]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-listener-rule"
  })
}

# =========================================================
# ECS Fargate Service
# Task definition is managed outside of Terraform
# (already created by user, refreshed via GitHub Actions),
# so we lifecycle-ignore task_definition changes.
# =========================================================
resource "aws_ecs_service" "test" {
  name            = "${local.name}-service"
  cluster         = data.aws_ecs_cluster.shared.arn
  task_definition = data.aws_ecs_task_definition.test.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.test_ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener_rule.test]

  tags = merge(local.common_tags, {
    Name = "${local.name}-service"
  })
}

# =========================================================
# Outputs
# =========================================================
output "test_ecs_service_name" {
  description = "Name of the dev-test ECS service"
  value       = aws_ecs_service.test.name
}

output "test_target_group_arn" {
  description = "Target group ARN for the dev-test service"
  value       = aws_lb_target_group.test.arn
}

output "test_security_group_id" {
  description = "Security group ID attached to the dev-test ECS tasks"
  value       = aws_security_group.test_ecs.id
}

output "test_listener_rule_arn" {
  description = "ALB listener rule ARN for the dev-test service"
  value       = aws_lb_listener_rule.test.arn
}
