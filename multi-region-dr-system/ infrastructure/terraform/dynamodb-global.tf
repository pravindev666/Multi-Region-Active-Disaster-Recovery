# DynamoDB Global Table - Mumbai (Primary)
resource "aws_dynamodb_table" "mumbai" {
  provider         = aws.mumbai
  name             = var.dynamodb_table_name
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  
  attribute {
    name = "id"
    type = "S"
  }
  
  attribute {
    name = "timestamp"
    type = "N"
  }
  
  global_secondary_index {
    name            = "timestamp-index"
    hash_key        = "timestamp"
    projection_type = "ALL"
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  server_side_encryption {
    enabled = true
  }
  
  tags = {
    Name = "${var.dynamodb_table_name}-mumbai"
  }
  
  replica {
    region_name = var.secondary_region
  }
}

# DynamoDB Global Table - Singapore (Replica)
# Note: The replica is automatically created by the replica block above
# This is a reference to track it in Terraform state

data "aws_dynamodb_table" "singapore" {
  provider = aws.singapore
  name     = var.dynamodb_table_name
  
  depends_on = [aws_dynamodb_table.mumbai]
}

# CloudWatch Alarm - Mumbai DynamoDB Throttles
resource "aws_cloudwatch_metric_alarm" "mumbai_dynamodb_throttles" {
  provider            = aws.mumbai
  alarm_name          = "mumbai-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = [aws_sns_topic.mumbai_alerts.arn]
  
  dimensions = {
    TableName = aws_dynamodb_table.mumbai.name
  }
}

# CloudWatch Alarm - Singapore DynamoDB Throttles
resource "aws_cloudwatch_metric_alarm" "singapore_dynamodb_throttles" {
  provider            = aws.singapore
  alarm_name          = "singapore-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttling events"
  alarm_actions       = [aws_sns_topic.singapore_alerts.arn]
  
  dimensions = {
    TableName = var.dynamodb_table_name
  }
}

# CloudWatch Alarm - Replication Latency
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  provider            = aws.mumbai
  alarm_name          = "dynamodb-replication-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000"
  alarm_description   = "Alert when replication latency exceeds 5 seconds"
  alarm_actions       = [aws_sns_topic.mumbai_alerts.arn]
  
  dimensions = {
    TableName              = aws_dynamodb_table.mumbai.name
    ReceivingRegion        = var.secondary_region
  }
}
