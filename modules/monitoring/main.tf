# CloudWatch Monitoring Module (Simplified)
resource "aws_sns_topic" "alerts" {
  count = var.create_sns_topic ? 1 : 0
  name  = "${var.project_name}-${var.environment}-alerts"
  tags  = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.create_sns_topic ? length(var.sns_email_endpoints) : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoints[count.index]
}

resource "aws_cloudwatch_log_group" "main" {
  count             = var.enable_alarms ? 1 : 0
  name              = "/aws/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

output "sns_topic_arn" {
  value = var.create_sns_topic ? aws_sns_topic.alerts[0].arn : null
}
