
#!/bin/bash

set -e

echo "=========================================="
echo "Multi-Region DR System Deployment Script"
echo "=========================================="

# Configuration
PRIMARY_REGION="ap-south-1"
SECONDARY_REGION="ap-southeast-1"
TERRAFORM_DIR="infrastructure/terraform"
LAMBDA_DIR="lambda"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        exit 1
    fi
    
    print_info "All prerequisites satisfied"
}

# Package Lambda functions
package_lambda_functions() {
    print_info "Packaging Lambda functions..."
    
    cd $LAMBDA_DIR
    
    for func_dir in */; do
        func_name=${func_dir%/}
        print_info "Packaging $func_name..."
        
        cd $func_name
        
        # Install dependencies if requirements.txt exists
        if [ -f "requirements.txt" ]; then
            pip3 install -r requirements.txt -t . --upgrade
        fi
        
        # Create zip file
        zip -r ../${func_name}.zip . -x "*.pyc" -x "__pycache__/*"
        
        cd ..
    done
    
    cd ..
    print_info "Lambda functions packaged successfully"
}

# Initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    
    cd $TERRAFORM_DIR
    terraform init
    cd ../..
    
    print_info "Terraform initialized"
}

# Validate Terraform configuration
validate_terraform() {
    print_info "Validating Terraform configuration..."
    
    cd $TERRAFORM_DIR
    terraform validate
    cd ../..
    
    print_info "Terraform configuration is valid"
}

# Plan Terraform deployment
plan_terraform() {
    print_info "Planning Terraform deployment..."
    
    cd $TERRAFORM_DIR
    terraform plan -out=tfplan
    cd ../..
    
    print_info "Terraform plan created"
}

# Apply Terraform configuration
apply_terraform() {
    print_info "Applying Terraform configuration..."
    
    cd $TERRAFORM_DIR
    terraform apply tfplan
    cd ../..
    
    print_info "Infrastructure deployed successfully"
}

# Deploy Lambda functions
deploy_lambda_functions() {
    print_info "Deploying Lambda functions..."
    
    # Mumbai region
    print_info "Deploying to Mumbai ($PRIMARY_REGION)..."
    
    aws lambda update-function-code \
        --function-name health-checker-mumbai \
        --zip-file fileb://$LAMBDA_DIR/health-checker.zip \
        --region $PRIMARY_REGION || print_warning "Failed to update health-checker-mumbai"
    
    aws lambda update-function-code \
        --function-name traffic-router-mumbai \
        --zip-file fileb://$LAMBDA_DIR/traffic-router.zip \
        --region $PRIMARY_REGION || print_warning "Failed to update traffic-router-mumbai"
    
    # Singapore region
    print_info "Deploying to Singapore ($SECONDARY_REGION)..."
    
    aws lambda update-function-code \
        --function-name health-checker-singapore \
        --zip-file fileb://$LAMBDA_DIR/health-checker.zip \
        --region $SECONDARY_REGION || print_warning "Failed to update health-checker-singapore"
    
    aws lambda update-function-code \
        --function-name traffic-router-singapore \
        --zip-file fileb://$LAMBDA_DIR/traffic-router.zip \
        --region $SECONDARY_REGION || print_warning "Failed to update traffic-router-singapore"
    
    print_info "Lambda functions deployed"
}

# Verify deployment
verify_deployment() {
    print_info "Verifying deployment..."
    
    # Check Mumbai ALB
    print_info "Checking Mumbai ALB..."
    aws elbv2 describe-load-balancers \
        --names mumbai-alb \
        --region $PRIMARY_REGION \
        --query 'LoadBalancers[0].State.Code' \
        --output text || print_error "Mumbai ALB not found"
    
    # Check Singapore ALB
    print_info "Checking Singapore ALB..."
    aws elbv2 describe-load-balancers \
        --names singapore-alb \
        --region $SECONDARY_REGION \
        --query 'LoadBalancers[0].State.Code' \
        --output text || print_error "Singapore ALB not found"
    
    # Check DynamoDB global table
    print_info "Checking DynamoDB global table..."
    aws dynamodb describe-table \
        --table-name dr-application-data \
        --region $PRIMARY_REGION \
        --query 'Table.TableStatus' \
        --output text || print_error "DynamoDB table not found"
    
    print_info "Deployment verification complete"
}

# Main deployment flow
main() {
    echo ""
    print_info "Starting deployment process..."
    echo ""
    
    check_prerequisites
    echo ""
    
    package_lambda_functions
    echo ""
    
    init_terraform
    echo ""
    
    validate_terraform
    echo ""
    
    plan_terraform
    echo ""
    
    # Ask for confirmation
    read -p "Do you want to proceed with deployment? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_warning "Deployment cancelled"
        exit 0
    fi
    
    apply_terraform
    echo ""
    
    deploy_lambda_functions
    echo ""
    
    verify_deployment
    echo ""
    
    print_info "=========================================="
    print_info "Deployment completed successfully!"
    print_info "=========================================="
    echo ""
    print_info "Next steps:"
    echo "  1. Verify Route 53 DNS records are correctly configured"
    echo "  2. Confirm SNS email subscriptions"
    echo "  3. Run health checks: cd testing && python3 rto-calculator.py"
    echo "  4. Test failover: cd scripts && ./test-failover.sh"
    echo ""
}

# Run main function
main
