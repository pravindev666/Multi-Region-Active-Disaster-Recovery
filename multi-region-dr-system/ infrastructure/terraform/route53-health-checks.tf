# Route 53 Health Checks are already defined in main.tf
# This file contains additional health check configurations

# CloudWatch Alarm for Mumbai Health Check
resource "aws_cloudwatch_metric_alarm" "mumbai_health_check" {
  provider            = aws.mumbai
  alarm_name          = "route53-mumbai-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Alert when Route 53 health check fails for Mumbai"
  alarm_actions       = [aws_sns_topic.mumbai_alerts.arn]
  
  dimensions = {
    HealthCheckId = aws_route53_health_check.mumbai_alb.id
  }
}

# CloudWatch Alarm for Singapore Health Check
resource "aws_cloudwatch_metric_alarm" "singapore_health_check" {
  provider            = aws.singapore
  alarm_name          = "route53-singapore-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Alert when Route 53 health check fails for Singapore"
  alarm_actions       = [aws_sns_topic.singapore_alerts.arn]
  
  dimensions = {
    HealthCheckId = aws_route53_health_check.singapore_alb.id
  }
}

# Route 53 Health Check for DynamoDB (custom endpoint)
resource "aws_route53_health_check" "mumbai_dynamodb" {
  type                            = "CALCULATED"
  child_health_threshold          = 1
  child_health_checks             = [aws_route53_health_check.mumbai_alb.id]
  insufficient_data_health_status = "Unhealthy"
  
  tags = {
    Name = "mumbai-dynamodb-health"
  }
}

resource "aws_route53_health_check" "singapore_dynamodb" {
  type                            = "CALCULATED"
  child_health_threshold          = 1
  child_health_checks             = [aws_route53_health_check.singapore_alb.id]
  insufficient_data_health_status = "Unhealthy"
  
  tags = {
    Name = "singapore-dynamodb-health"
  }
}
