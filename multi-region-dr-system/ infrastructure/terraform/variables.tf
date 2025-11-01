variable "primary_region" {
  description = "Primary AWS region (Mumbai)"
  type        = string
  default     = "ap-south-1"
}

variable "secondary_region" {
  description = "Secondary AWS region (Singapore)"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB global table"
  type        = string
  default     = "dr-application-data"
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}
