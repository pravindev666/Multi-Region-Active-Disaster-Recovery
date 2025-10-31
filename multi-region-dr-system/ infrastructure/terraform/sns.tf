# Mumbai SNS Topic
resource "aws_sns_topic" "mumbai_alerts" {
  provider = aws.mumbai
  name     = "dr-alerts-mumbai"
  
  tags = {
    Name = "mumbai-alerts"
  }
}

# Singapore SNS Topic
resource "aws_sns_topic" "singapore_alerts" {
  provider = aws.singapore
  name     = "dr-alerts-singapore"
  
  tags = {
    Name = "singapore-alerts"
  }
}

# SNS Email Subscription - Mumbai
resource "aws_sns_topic_subscription" "mumbai_email" {
  provider  = aws.mumbai
  topic_arn = aws_sns_topic.mumbai_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS Email Subscription - Singapore
resource "aws_sns_topic_subscription" "singapore_email" {
  provider  = aws.singapore
  topic_arn = aws_sns_topic.singapore_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Alarm - Mumbai Lambda Errors
resource "aws_cloudwatch_metric_alarm" "mumbai_lambda_errors" {
  provider            = aws.mumbai
  alarm_name          = "mumbai-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when Lambda errors exceed threshold"
  alarm_actions       = [aws_sns_topic.mumbai_alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.mumbai_traffic_router.function_name
  }
}

# CloudWatch Alarm - Singapore Lambda Errors
resource "aws_cloudwatch_metric_alarm" "singapore_lambda_errors" {
  provider            = aws.singapore
  alarm_name          = "singapore-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when Lambda errors exceed threshold"
  alarm_actions       = [aws_sns_topic.singapore_alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.singapore_traffic_router.function_name
  }
}

# CloudWatch Alarm - Mumbai ALB Unhealthy Targets
resource "aws_cloudwatch_metric_alarm" "mumbai_unhealthy_targets" {
  provider            = aws.mumbai
  alarm_name          = "mumbai-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Alert when ALB has unhealthy targets"
  alarm_actions       = [aws_sns_topic.mumbai_alerts.arn]
  
  dimensions = {
    LoadBalancer = aws_lb.mumbai_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.mumbai_lambda.arn_suffix
  }
}

# CloudWatch Alarm - Singapore ALB Unhealthy Targets
resource "aws_cloudwatch_metric_alarm" "singapore_unhealthy_targets" {
  provider            = aws.singapore
  alarm_name          = "singapore-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Alert when ALB has unhealthy targets"
  alarm_actions       = [aws_sns_topic.singapore_alerts.arn]
  
  dimensions = {
    LoadBalancer = aws_lb.singapore_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.singapore_lambda.arn_suffix
  }
}
