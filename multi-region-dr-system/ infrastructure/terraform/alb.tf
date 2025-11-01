# Security Group for Mumbai ALB
resource "aws_security_group" "mumbai_alb" {
  provider    = aws.mumbai
  name        = "mumbai-alb-sg"
  description = "Security group for Mumbai ALB"
  vpc_id      = aws_vpc.mumbai.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  
  tags = {
    Name = "mumbai-alb-sg"
  }
}

# Security Group for Singapore ALB
resource "aws_security_group" "singapore_alb" {
  provider
