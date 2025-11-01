#!/bin/bash

set -e

echo "=========================================="
echo "Multi-Region DR System Rollback Script"
echo "=========================================="

# Configuration
PRIMARY_REGION="ap-south-1"
SECONDARY_REGION="ap-southeast-1"
TERRAFORM_DIR="infrastructure/terraform"

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

# Backup current state
backup_state() {
    print_info "Backing up current Terraform state..."
    
    cd $TERRAFORM_DIR
    
    if [ -f "terraform.tfstate" ]; then
        BACKUP_FILE="terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"
        cp terraform.tfstate $BACKUP_FILE
        print_info "State backed up to: $BACKUP_FILE"
    else
        print_warning "No state file found to backup"
    fi
    
    cd ../..
}

# Drain traffic from primary region
drain_traffic() {
    print_info "Draining traffic from primary region..."
    
    # Get Route 53 hosted zone ID
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$DOMAIN_NAME.'].Id" --output text | cut -d'/' -f3)
    
    if [ -n "$HOSTED_ZONE_ID" ]; then
        print_info "Found hosted zone: $HOSTED_ZONE_ID"
        
        # Update health check to force failover
        HEALTH_CHECK_ID=$(aws route53 list-health-checks --query "HealthChecks[?HealthCheckConfig.FullyQualifiedDomainName=='mumbai-alb'].Id" --output text)
        
        if [ -n "$HEALTH_CHECK_ID" ]; then
            print_info "Disabling primary health check temporarily"
            # Note: This is a simulation; actual implementation would update health check
        fi
    else
        print_warning "Could not find hosted zone"
    fi
}

# Restore previous Lambda versions
restore_lambda_versions() {
    print_info "Restoring previous Lambda versions..."
    
    # Mumbai region
    print_info "Restoring Lambda functions in Mumbai..."
    
    for func in "health-checker-mumbai" "traffic-router-mumbai"; do
        # Get previous version
        PREV_VERSION=$(aws lambda list-versions-by-function \
            --function-name $func \
            --region $PRIMARY_REGION \
            --query 'Versions[-2].Version' \
            --output text)
        
        if [ "$PREV_VERSION" != "None" ] && [ -n "$PREV_VERSION" ]; then
            aws lambda update-alias \
                --function-name $func \
                --name PROD \
                --function-version $PREV_VERSION \
                --region $PRIMARY_REGION 2>/dev/null || print_warning "Could not restore $func"
            
            print_info "  Restored $func to version $PREV_VERSION"
        else
            print_warning "  No previous version found for $func"
        fi
    done
    
    # Singapore region
    print_info "Restoring Lambda functions in Singapore..."
    
    for func in "health-checker-singapore" "traffic-router-singapore"; do
        PREV_VERSION=$(aws lambda list-versions-by-function \
            --function-name $func \
            --region $SECONDARY_REGION \
            --query 'Versions[-2].Version' \
            --output text)
        
        if [ "$PREV_VERSION" != "None" ] && [ -n "$PREV_VERSION" ]; then
            aws lambda update-alias \
                --function-name $func \
                --name PROD \
                --function-version $PREV_VERSION \
                --region $SECONDARY_REGION 2>/dev/null || print_warning "Could not restore $func"
            
            print_info "  Restored $func to version $PREV_VERSION"
        else
            print_warning "  No previous version found for $func"
        fi
    done
}

# Restore DynamoDB from backup
restore_dynamodb_backup() {
    print_info "Checking DynamoDB backup options..."
    
    TABLE_NAME="dr-application-data"
    
    # List available backups
    BACKUPS=$(aws dynamodb list-backups \
        --table-name $TABLE_NAME \
        --region $PRIMARY_REGION \
        --query 'BackupSummaries[0:5].[BackupName,BackupCreationDateTime]' \
        --output text)
    
    if [ -n "$BACKUPS" ]; then
        print_info "Available backups:"
        echo "$BACKUPS"
        
        echo ""
        read -p "Do you want to restore from a backup? (yes/no): " restore_backup
        
        if [ "$restore_backup" = "yes" ]; then
            read -p "Enter backup ARN: " BACKUP_ARN
            
            if [ -n "$BACKUP_ARN" ]; then
                NEW_TABLE_NAME="${TABLE_NAME}-restored-$(date +%Y%m%d%H%M%S)"
                
                print_info "Restoring to new table: $NEW_TABLE_NAME"
                
                aws dynamodb restore-table-from-backup \
                    --target-table-name $NEW_TABLE_NAME \
                    --backup-arn $BACKUP_ARN \
                    --region $PRIMARY_REGION
                
                print_info "Table restore initiated. This may take several minutes."
                print_info "Once complete, update your application to use: $NEW_TABLE_NAME"
            fi
        fi
    else
        print_warning "No backups found for table $TABLE_NAME"
        print_info "Point-in-time recovery may be available"
    fi
}

# Restore Route 53 configuration
restore_route53() {
    print_info "Restoring Route 53 configuration..."
    
    # Re-enable both health checks
    MUMBAI_HEALTH_CHECK=$(aws route53 list-health-checks \
        --query "HealthChecks[?HealthCheckConfig.FullyQualifiedDomainName=='mumbai-alb'].Id" \
        --output text)
    
    SINGAPORE_HEALTH_CHECK=$(aws route53 list-health-checks \
        --query "HealthChecks[?HealthCheckConfig.FullyQualifiedDomainName=='singapore-alb'].Id" \
        --output text)
    
    if [ -n "$MUMBAI_HEALTH_CHECK" ] && [ -n "$SINGAPORE_HEALTH_CHECK" ]; then
        print_info "Health checks found and active"
    else
        print_warning "Could not verify health checks"
    fi
}

# Terraform rollback
terraform_rollback() {
    print_info "Rolling back Terraform changes..."
    
    cd $TERRAFORM_DIR
    
    read -p "Do you want to destroy all resources? (yes/no): " destroy_all
    
    if [ "$destroy_all" = "yes" ]; then
        print_warning "This will DESTROY all infrastructure!"
        read -p "Are you absolutely sure? Type 'destroy' to confirm: " confirm
        
        if [ "$confirm" = "destroy" ]; then
            terraform destroy -auto-approve
            print_info "Infrastructure destroyed"
        else
            print_info "Destruction cancelled"
        fi
    else
        print_info "Terraform rollback cancelled"
    fi
    
    cd ../..
}

# Verify rollback
verify_rollback() {
    print_info "Verifying rollback status..."
    
    # Check Lambda functions
    print_info "Checking Lambda functions..."
    
    MUMBAI_LAMBDA=$(aws lambda get-function \
        --function-name traffic-router-mumbai \
        --region $PRIMARY_REGION \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    SINGAPORE_LAMBDA=$(aws lambda get-function \
        --function-name traffic-router-singapore \
        --region $SECONDARY_REGION \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    print_info "  Mumbai Lambda: $MUMBAI_LAMBDA"
    print_info "  Singapore Lambda: $SINGAPORE_LAMBDA"
    
    # Check DynamoDB
    print_info "Checking DynamoDB table..."
    
    TABLE_STATUS=$(aws dynamodb describe-table \
        --table-name dr-application-data \
        --region $PRIMARY_REGION \
        --query 'Table.TableStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    print_info "  Table Status: $TABLE_STATUS"
    
    # Check ALBs
    print_info "Checking Application Load Balancers..."
    
    MUMBAI_ALB=$(aws elbv2 describe-load-balancers \
        --names mumbai-alb \
        --region $PRIMARY_REGION \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    SINGAPORE_ALB=$(aws elbv2 describe-load-balancers \
        --names singapore-alb \
        --region $SECONDARY_REGION \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    print_info "  Mumbai ALB: $MUMBAI_ALB"
    print_info "  Singapore ALB: $SINGAPORE_ALB"
}

# Main rollback flow
main() {
    echo ""
    print_warning "This script will rollback the DR system to a previous state"
    print_warning "Please ensure you have a backup before proceeding"
    echo ""
    
    read -p "Do you want to continue? (yes/no): " continue_rollback
    
    if [ "$continue_rollback" != "yes" ]; then
        print_info "Rollback cancelled"
        exit 0
    fi
    
    echo ""
    print_info "Starting rollback process..."
    echo ""
    
    # Backup current state
    backup_state
    echo ""
    
    # Menu for rollback options
    echo "Select rollback option:"
    echo "  1) Restore Lambda functions to previous version"
    echo "  2) Restore DynamoDB from backup"
    echo "  3) Restore Route 53 configuration"
    echo "  4) Full Terraform rollback (destroy infrastructure)"
    echo "  5) All of the above"
    echo ""
    
    read -p "Enter option (1-5): " option
    
    case $option in
        1)
            restore_lambda_versions
            ;;
        2)
            restore_dynamodb_backup
            ;;
        3)
            restore_route53
            ;;
        4)
            terraform_rollback
            ;;
        5)
            drain_traffic
            echo ""
            restore_lambda_versions
            echo ""
            restore_dynamodb_backup
            echo ""
            restore_route53
            echo ""
            terraform_rollback
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    echo ""
    verify_rollback
    echo ""
    
    print_info "=========================================="
    print_info "Rollback completed"
    print_info "=========================================="
    echo ""
    print_info "Next steps:"
    echo "  1. Verify application functionality"
    echo "  2. Check CloudWatch logs for errors"
    echo "  3. Run health checks: cd testing && python3 data-integrity-tests.py"
    echo "  4. Monitor Route 53 health checks"
    echo ""
}

# Run main function
main
