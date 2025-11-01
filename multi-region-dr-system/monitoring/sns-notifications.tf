# SNS resources are already defined in sns.tf
# This file contains additional SNS notification configurations

# SNS Topic Policy - Mumbai
resource "aws_sns_topic_policy" "mumbai_alerts_policy" {
  provider = aws.mumbai
  arn      = aws_sns_topic.mumbai_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "lambda.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.mumbai_alerts.arn
      }
    ]
  })
}

# SNS Topic Policy - Singapore
resource "aws_sns_topic_policy" "singapore_alerts_policy" {
  provider = aws.singapore
  arn      = aws_sns_topic.singapore_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.amazonaws.com",
            "lambda.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.singapore_alerts.arn
      }
    ]
  })
}

# CloudWatch Event Rule for Scheduled Health Checks - Mumbai
resource "aws_cloudwatch_event_rule" "mumbai_scheduled_health_check" {
  provider            = aws.mumbai
  name                = "scheduled-health-check-mumbai"
  description         = "Trigger health check every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

# CloudWatch Event Target - Mumbai
resource "aws_cloudwatch_event_target" "mumbai_health_check_target" {
  provider  = aws.mumbai
  rule      = aws_cloudwatch_event_rule.mumbai_scheduled_health_check.name
  target_id = "TriggerHealthChecker"
  arn       = aws_lambda_function.mumbai_health_checker.arn
}

# Lambda Permission for CloudWatch Events - Mumbai
resource "aws_lambda_permission" "mumbai_health_check_event" {
  provider      = aws.mumbai
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mumbai_health_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mumbai_scheduled_health_check.arn
}

# CloudWatch Event Rule for Scheduled Health Checks - Singapore
resource "aws_cloudwatch_event_rule" "singapore_scheduled_health_check" {
  provider            = aws.singapore
  name                = "scheduled-health-check-singapore"
  description         = "Trigger health check every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

# CloudWatch Event Target - Singapore
resource "aws_cloudwatch_event_target" "singapore_health_check_target" {
  provider  = aws.singapore
  rule      = aws_cloudwatch_event_rule.singapore_scheduled_health_check.name
  target_id = "TriggerHealthChecker"
  arn       = aws_lambda_function.singapore_health_checker.arn
}

# Lambda Permission for CloudWatch Events - Singapore
resource "aws_lambda_permission" "singapore_health_check_event" {
  provider      = aws.singapore
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.singapore_health_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.singapore_scheduled_health_check.arn
}
