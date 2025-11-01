output "mumbai_alb_dns" {
  description = "DNS name of Mumbai Application Load Balancer"
  value       = aws_lb.mumbai_alb.dns_name
}

output "singapore_alb_dns" {
  description = "DNS name of Singapore Application Load Balancer"
  value       = aws_lb.singapore_alb.dns_name
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_nameservers" {
  description = "Route 53 nameservers for domain configuration"
  value       = aws_route53_zone.main.name_servers
}

output "primary_endpoint" {
  description = "Primary API endpoint"
  value       = "https://api.${var.domain_name}"
}

output "dynamodb_table_name" {
  description = "DynamoDB global table name"
  value       = aws_dynamodb_table.mumbai.name
}

output "mumbai_lambda_functions" {
  description = "Mumbai Lambda function ARNs"
  value = {
    health_checker  = aws_lambda_function.mumbai_health_checker.arn
    traffic_router  = aws_lambda_function.mumbai_traffic_router.arn
  }
}

output "singapore_lambda_functions" {
  description = "Singapore Lambda function ARNs"
  value = {
    health_checker  = aws_lambda_function.singapore_health_checker.arn
    traffic_router  = aws_lambda_function.singapore_traffic_router.arn
  }
}

output "sns_topics" {
  description = "SNS topic ARNs for alerts"
  value = {
    mumbai    = aws_sns_topic.mumbai_alerts.arn
    singapore = aws_sns_topic.singapore_alerts.arn
  }
}

output "health_check_ids" {
  description = "Route 53 health check IDs"
  value = {
    mumbai    = aws_route53_health_check.mumbai_alb.id
    singapore = aws_route53_health_check.singapore_alb.id
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    primary_region   = var.primary_region
    secondary_region = var.secondary_region
    endpoint         = "https://api.${var.domain_name}"
    regions_active   = 2
  }
}
