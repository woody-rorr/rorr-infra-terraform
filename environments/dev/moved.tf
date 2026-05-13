# Terraform 리소스 식별자 변경 - state migration
# 이 파일은 apply 완료 후 삭제해도 됩니다.

moved {
  from = aws_iam_role.rorr_mcp_orchestrator_execution
  to   = aws_iam_role.execution
}

moved {
  from = aws_iam_role.rorr_mcp_orchestrator_task
  to   = aws_iam_role.task
}

moved {
  from = aws_iam_role_policy_attachment.rorr_mcp_orchestrator_execution_policy
  to   = aws_iam_role_policy_attachment.execution_policy
}

moved {
  from = aws_iam_role_policy.rorr_mcp_orchestrator_bedrock
  to   = aws_iam_role_policy.bedrock
}

moved {
  from = aws_cloudwatch_log_group.rorr_mcp_orchestrator
  to   = aws_cloudwatch_log_group.orchestrator
}

moved {
  from = aws_lb_target_group.rorr_mcp_orchestrator
  to   = aws_lb_target_group.orchestrator
}

moved {
  from = aws_ecs_task_definition.rorr_mcp_orchestrator
  to   = aws_ecs_task_definition.orchestrator
}
