# IAM Module - Placeholder for future implementation
# To be completed with full IAM roles for ECS, RDS, GitHub Actions OIDC, etc.

resource "null_resource" "iam_placeholder" {
  triggers = {
    placeholder = "IAM module to be implemented"
  }
}

output "ecs_task_execution_role_arn" {
  value = ""  # Placeholder
}

output "ecs_task_role_arn" {
  value = ""  # Placeholder
}

output "rds_monitoring_role_arn" {
  value = ""  # Placeholder
}

output "github_actions_role_arn" {
  value = ""  # Placeholder
}

