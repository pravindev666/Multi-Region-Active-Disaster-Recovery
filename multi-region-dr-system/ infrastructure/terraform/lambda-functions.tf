# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "dr-lambda-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda Functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "dr-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.mumbai.arn,
          "${aws_dynamodb_table.mumbai.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Mumbai Lambda - Health Checker
resource "aws_lambda_function" "mumbai_health_checker" {
  provider      = aws.mumbai
  filename      = "${path.module}/../../lambda/health-checker.zip"
  function_name = "health-checker-mumbai"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
      REGION     = var.primary_region
      SNS_TOPIC  = aws_sns_topic.mumbai_alerts.arn
    }
  }
  
  tags = {
    Name = "mumbai-health-checker"
  }
}

# Singapore Lambda - Health Checker
resource "aws_lambda_function" "singapore_health_checker" {
  provider      = aws.singapore
  filename      = "${path.module}/../../lambda/health-checker.zip"
  function_name = "health-checker-singapore"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
      REGION     = var.secondary_region
      SNS_TOPIC  = aws_sns_topic.singapore_alerts.arn
    }
  }
  
  tags = {
    Name = "singapore-health-checker"
  }
}

# Mumbai Lambda - Traffic Router
resource "aws_lambda_function" "mumbai_traffic_router" {
  provider      = aws.mumbai
  filename      = "${path.module}/../../lambda/traffic-router.zip"
  function_name = "traffic-router-mumbai"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
      REGION     = var.primary_region
    }
  }
  
  tags = {
    Name = "mumbai-traffic-router"
  }
}

# Singapore Lambda - Traffic Router
resource "aws_lambda_function" "singapore_traffic_router" {
  provider      = aws.singapore
  filename      = "${path.module}/../../lambda/traffic-router.zip"
  function_name = "traffic-router-singapore"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
      REGION     = var.secondary_region
    }
  }
  
  tags = {
    Name = "singapore-traffic-router"
  }
}

# Lambda Permission for ALB - Mumbai
resource "aws_lambda_permission" "mumbai_alb" {
  provider      = aws.mumbai
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mumbai_traffic_router.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.mumbai_lambda.arn
}

# Lambda Permission for ALB - Singapore
resource "aws_lambda_permission" "singapore_alb" {
  provider      = aws.singapore
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.singapore_traffic_router.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.singapore_lambda.arn
}

# Attach Lambda to Target Group - Mumbai
resource "aws_lb_target_group_attachment" "mumbai_lambda" {
  provider         = aws.mumbai
  target_group_arn = aws_lb_target_group.mumbai_lambda.arn
  target_id        = aws_lambda_function.mumbai_traffic_router.arn
  depends_on       = [aws_lambda_permission.mumbai_alb]
}

# Attach Lambda to Target Group - Singapore
resource "aws_lb_target_group_attachment" "singapore_lambda" {
  provider         = aws.singapore
  target_group_arn = aws_lb_target_group.singapore_lambda.arn
  target_id        = aws_lambda_function.singapore_traffic_router.arn
  depends_on       = [aws_lambda_permission.singapore_alb]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "mumbai_health_checker" {
  provider          = aws.mumbai
  name              = "/aws/lambda/${aws_lambda_function.mumbai_health_checker.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "singapore_health_checker" {
  provider          = aws.singapore
  name              = "/aws/lambda/${aws_lambda_function.singapore_health_checker.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "mumbai_traffic_router" {
  provider          = aws.mumbai
  name              = "/aws/lambda/${aws_lambda_function.mumbai_traffic_router.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "singapore_traffic_router" {
  provider          = aws.singapore
  name              = "/aws/lambda/${aws_lambda_function.singapore_traffic_router.function_name}"
  retention_in_days = 7
}
