terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "dr-system-terraform-state"
    key            = "multi-region-dr/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  alias  = "mumbai"
  region = var.primary_region
  
  default_tags {
    tags = {
      Project     = "MultiRegionDR"
      ManagedBy   = "Terraform"
      Environment = var.environment
      CostCenter  = "Infrastructure"
    }
  }
}

provider "aws" {
  alias  = "singapore"
  region = var.secondary_region
  
  default_tags {
    tags = {
      Project     = "MultiRegionDR"
      ManagedBy   = "Terraform"
      Environment = var.environment
      CostCenter  = "Infrastructure"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project     = "MultiRegionDR"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
