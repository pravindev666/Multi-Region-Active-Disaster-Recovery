terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary Region Provider - Mumbai
provider "aws" {
  alias  = "mumbai"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "Multi-Region-DR"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary Region Provider - Singapore
provider "aws" {
  alias  = "singapore"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = "Multi-Region-DR"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Global Route 53 Resources
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# Health Check for Mumbai ALB
resource "aws_route53_health_check" "mumbai_alb" {
  fqdn              = aws_lb.mumbai_alb.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "mumbai-alb-health-check"
  }
}

# Health Check for Singapore ALB
resource "aws_route53_health_check" "singapore_alb" {
  fqdn              = aws_lb.singapore_alb.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "singapore-alb-health-check"
  }
}

# Primary DNS Record - Mumbai
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  
  set_identifier  = "primary-mumbai"
  health_check_id = aws_route53_health_check.mumbai_alb.id
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  alias {
    name                   = aws_lb.mumbai_alb.dns_name
    zone_id                = aws_lb.mumbai_alb.zone_id
    evaluate_target_health = true
  }
}

# Secondary DNS Record - Singapore
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  
  set_identifier = "secondary-singapore"
  health_check_id = aws_route53_health_check.singapore_alb.id
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.singapore_alb.dns_name
    zone_id                = aws_lb.singapore_alb.zone_id
    evaluate_target_health = true
  }
}

# Mumbai VPC
resource "aws_vpc" "mumbai" {
  provider             = aws.mumbai
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "mumbai-vpc"
  }
}

# Mumbai Subnets
resource "aws_subnet" "mumbai_public_1" {
  provider          = aws.mumbai
  vpc_id            = aws_vpc.mumbai.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.primary_region}a"
  
  tags = {
    Name = "mumbai-public-1"
  }
}

resource "aws_subnet" "mumbai_public_2" {
  provider          = aws.mumbai
  vpc_id            = aws_vpc.mumbai.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.primary_region}b"
  
  tags = {
    Name = "mumbai-public-2"
  }
}

# Singapore VPC
resource "aws_vpc" "singapore" {
  provider             = aws.singapore
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "singapore-vpc"
  }
}

# Singapore Subnets
resource "aws_subnet" "singapore_public_1" {
  provider          = aws.singapore
  vpc_id            = aws_vpc.singapore.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "${var.secondary_region}a"
  
  tags = {
    Name = "singapore-public-1"
  }
}

resource "aws_subnet" "singapore_public_2" {
  provider          = aws.singapore
  vpc_id            = aws_vpc.singapore.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "${var.secondary_region}b"
  
  tags = {
    Name = "singapore-public-2"
  }
}

# Internet Gateways
resource "aws_internet_gateway" "mumbai" {
  provider = aws.mumbai
  vpc_id   = aws_vpc.mumbai.id
  
  tags = {
    Name = "mumbai-igw"
  }
}

resource "aws_internet_gateway" "singapore" {
  provider = aws.singapore
  vpc_id   = aws_vpc.singapore.id
  
  tags = {
    Name = "singapore-igw"
  }
}

# Route Tables
resource "aws_route_table" "mumbai_public" {
  provider = aws.mumbai
  vpc_id   = aws_vpc.mumbai.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mumbai.id
  }
  
  tags = {
    Name = "mumbai-public-rt"
  }
}

resource "aws_route_table" "singapore_public" {
  provider = aws.singapore
  vpc_id   = aws_vpc.singapore.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.singapore.id
  }
  
  tags = {
    Name = "singapore-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "mumbai_1" {
  provider       = aws.mumbai
  subnet_id      = aws_subnet.mumbai_public_1.id
  route_table_id = aws_route_table.mumbai_public.id
}

resource "aws_route_table_association" "mumbai_2" {
  provider       = aws.mumbai
  subnet_id      = aws_subnet.mumbai_public_2.id
  route_table_id = aws_route_table.mumbai_public.id
}

resource "aws_route_table_association" "singapore_1" {
  provider       = aws.singapore
  subnet_id      = aws_subnet.singapore_public_1.id
  route_table_id = aws_route_table.singapore_public.id
}

resource "aws_route_table_association" "singapore_2" {
  provider       = aws.singapore
  subnet_id      = aws_subnet.singapore_public_2.id
  route_table_id = aws_route_table.singapore_public.id
}
