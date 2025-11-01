#!/bin/bash

set -e

echo "=========================================="
echo "Multi-Region DR Failover Test"
echo "=========================================="

# Configuration
PRIMARY_REGION="ap-south-1"
SECONDARY_REGION="ap-southeast-1"
PRIMARY_ALB_NAME="mumbai-alb"
SECONDARY_ALB_NAME="singapore-alb"
DOMAIN_NAME="${1:-api.example.com}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        exit 1
    fi
    
    print_info "All prerequisites satisfied"
}

# Get ALB DNS names
get_alb_dns() {
    print_step "Getting ALB DNS names..."
    
    PRIMARY_ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names $PRIMARY_ALB_NAME \
        --region $PRIMARY_REGION \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null)
    
    SECONDARY_ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names $SECONDARY_ALB_NAME \
        --region $SECONDARY_REGION \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null)
    
    if [ -z "$PRIMARY_ALB_DNS" ] || [ -z "$SECONDARY_ALB_DNS" ]; then
        print_error "Could not retrieve ALB DNS names"
        exit 1
    fi
    
    print_info "Primary ALB: $PRIMARY_ALB_DNS"
    print_info "Secondary ALB: $SECONDARY_ALB_DNS"
}

# Check initial health status
check_initial_health() {
    print_step "Checking initial health status..."
    
    # Check primary region
    PRIMARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "https://$PRIMARY_ALB_DNS/health" || echo "000")
    
    # Check secondary region
    SECONDARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "https://$SECONDARY_ALB_DNS/health" || echo "000")
    
    print_info "Primary health status: $PRIMARY_HEALTH"
    print_info "Secondary health status: $SECONDARY_HEALTH"
    
    if [ "$PRIMARY_HEALTH" != "200" ] || [ "$SECONDARY_HEALTH" != "200" ]; then
        print_error "Both regions must be healthy before testing"
        exit 1
    fi
}

# Get target group ARN
get_target_group_arn() {
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --names $PRIMARY_ALB_NAME \
        --region $PRIMARY_REGION \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
        --load-balancer-arn $ALB_ARN \
        --region $PRIMARY_REGION \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo $TARGET_GROUP_ARN
}

# Get registered targets
get_registered_targets() {
    TG_ARN=$1
    
    aws elbv2 describe-target-health \
        --target-group-arn $TG_ARN \
        --region $PRIMARY_REGION \
        --query 'TargetHealthDescriptions[*].Target.Id' \
        --output text
}

# Simulate primary region failure
simulate_failure() {
    print_step "Simulating primary region failure..."
    
    TARGET_GROUP_ARN=$(get_target_group_arn)
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        print_error "Could not get target group ARN"
        exit 1
    fi
    
    print_info "Target Group: $TARGET_GROUP_ARN"
    
    # Get all targets
    TARGETS=$(get_registered_targets $TARGET_GROUP_ARN)
    
    if [ -z "$TARGETS" ]; then
        print_warning "No targets found in target group"
        return
    fi
    
    # Deregister all targets
    print_info "Deregistering targets from primary region..."
    
    for TARGET_ID in $TARGETS; do
        aws elbv2 deregister-targets \
            --target-group-arn $TARGET_GROUP_ARN \
            --targets Id=$TARGET_ID \
            --region $PRIMARY_REGION
        
        print_info "  Deregistered: $TARGET_ID"
    done
    
    # Store targets for restoration
    echo "$TARGETS" > /tmp/dr_test_targets.txt
    echo "$TARGET_GROUP_ARN" > /tmp/dr_test_tg_arn.txt
    
    print_info "Primary region failure simulated"
}

# Monitor failover
monitor_failover() {
    print_step "Monitoring failover process..."
    
    FAILOVER_START=$(date +%s)
    MAX_WAIT=180
    CHECK_INTERVAL=5
    CONSECUTIVE_SUCCESS=0
    REQUIRED_SUCCESS=3
    
    echo ""
    print_info "Monitoring endpoint: https://$DOMAIN_NAME/health"
    echo ""
    
    while [ $(($(date +%s) - FAILOVER_START)) -lt $MAX_WAIT ]; do
        ELAPSED=$(($(date +%s) - FAILOVER_START))
        
        # Try to reach the endpoint
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/health" --connect-timeout 5 || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            CONSECUTIVE_SUCCESS=$((CONSECUTIVE_SUCCESS + 1))
            echo -e "${GREEN}[$ELAPSED s]${NC} Status: $HTTP_CODE - SUCCESS ($CONSECUTIVE_SUCCESS/$REQUIRED_SUCCESS)"
            
            if [ $CONSECUTIVE_SUCCESS -ge $REQUIRED_SUCCESS ]; then
                FAILOVER_TIME=$ELAPSED
                print_info ""
                print_info "Failover completed successfully!"
                print_info "Total failover time: ${FAILOVER_TIME} seconds"
                
                if [ $FAILOVER_TIME -le 60 ]; then
                    print_info "RTO Target MET: ${FAILOVER_TIME}s <= 60s"
                else
                    print_warning "RTO Target EXCEEDED: ${FAILOVER_TIME}s > 60s"
                fi
                
                return 0
            fi
        else
            CONSECUTIVE_SUCCESS=0
            echo -e "${RED}[$ELAPSED s]${NC} Status: $HTTP_CODE - FAILED"
        fi
        
        sleep $CHECK_INTERVAL
    done
    
    print_error "Failover did not complete within ${MAX_WAIT} seconds"
    return 1
}

# Restore primary region
restore_primary_region() {
    print_step "Restoring primary region..."
    
    if [ ! -f /tmp/dr_test_targets.txt ] || [ ! -f /tmp/dr_test_tg_arn.txt ]; then
        print_warning "No backup data found. Cannot restore automatically."
        return
    fi
    
    TARGET_GROUP_ARN=$(cat /tmp/dr_test_tg_arn.txt)
    TARGETS=$(cat /tmp/dr_test_targets.txt)
    
    print_info "Re-registering targets..."
    
    for TARGET_ID in $TARGETS; do
        aws elbv2 register-targets \
            --target-group-arn $TARGET_GROUP_ARN \
            --targets Id=$TARGET_ID \
            --region $PRIMARY_REGION
        
        print_info "  Re-registered: $TARGET_ID"
    done
    
    # Wait for targets to become healthy
    print_info "Waiting for targets to become healthy..."
    sleep 30
    
    # Verify health
    HEALTHY_COUNT=$(aws elbv2 describe-target-health \
        --target-group-arn $TARGET_GROUP_ARN \
        --region $PRIMARY_REGION \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
        --output text)
    
    print_info "Healthy targets: $HEALTHY_COUNT"
    
    # Cleanup temp files
    rm -f /tmp/dr_test_targets.txt /tmp/dr_test_tg_arn.txt
    
    print_info "Primary region restored"
}

# Collect metrics
collect_metrics() {
    print_step "Collecting post-failover metrics..."
    
    # Test response times
    print_info "Measuring response times..."
    
    RESPONSE_TIMES=()
    
    for i in {1..10}; do
        START=$(date +%s%N)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/health" || echo "000")
        END=$(date +%s%N)
        
        if [ "$HTTP_CODE" = "200" ]; then
            RESPONSE_TIME=$(( (END - START) / 1000000 ))
            RESPONSE_TIMES+=($RESPONSE_TIME)
            echo "  Test $i: ${RESPONSE_TIME}ms"
        fi
        
        sleep 1
    done
    
    # Calculate average
    if [ ${#RESPONSE_TIMES[@]} -gt 0 ]; then
        SUM=0
        for TIME in "${RESPONSE_TIMES[@]}"; do
            SUM=$((SUM + TIME))
        done
        AVG=$((SUM / ${#RESPONSE_TIMES[@]}))
        
        print_info "Average response time: ${AVG}ms"
    fi
}

# Generate report
generate_report() {
    print_step "Generating test report..."
    
    REPORT_FILE="failover-test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > $REPORT_FILE << EOF
========================================
DR Failover Test Report
========================================

Test Date: $(date)
Primary Region: $PRIMARY_REGION
Secondary Region: $SECONDARY_REGION
Domain: $DOMAIN_NAME

Test Results:
-------------
Failover Time: ${FAILOVER_TIME}s
Target RTO: 60s
Status: $([ $FAILOVER_TIME -le 60 ] && echo "PASS" || echo "FAIL")

Average Response Time: ${AVG}ms

Primary Region:
  ALB: $PRIMARY_ALB_NAME
  DNS: $PRIMARY_ALB_DNS

Secondary Region:
  ALB: $SECONDARY_ALB_NAME
  DNS: $SECONDARY_ALB_DNS

========================================
EOF
    
    print_info "Report saved to: $REPORT_FILE"
    cat $REPORT_FILE
}

# Main test flow
main() {
    echo ""
    print_warning "This script will simulate a regional failure"
    print_warning "Ensure you have proper backups before proceeding"
    echo ""
    
    if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "api.example.com" ]; then
        print_error "Please provide domain name as argument"
        echo "Usage: ./test-failover.sh your-domain.com"
        exit 1
    fi
    
    read -p "Do you want to continue? (yes/no): " continue_test
    
    if [ "$continue_test" != "yes" ]; then
        print_info "Test cancelled"
        exit 0
    fi
    
    echo ""
    check_prerequisites
    echo ""
    
    get_alb_dns
    echo ""
    
    check_initial_health
    echo ""
    
    simulate_failure
    echo ""
    
    sleep 10
    
    if monitor_failover; then
        echo ""
        collect_metrics
        echo ""
        
        read -p "Do you want to restore the primary region? (yes/no): " restore
        
        if [ "$restore" = "yes" ]; then
            echo ""
            restore_primary_region
        fi
        
        echo ""
        generate_report
        echo ""
        
        print_info "=========================================="
        print_info "Failover test completed successfully"
        print_info "=========================================="
    else
        print_error "Failover test failed"
        
        read -p "Do you want to restore the primary region? (yes/no): " restore
        
        if [ "$restore" = "yes" ]; then
            restore_primary_region
        fi
        
        exit 1
    fi
}

# Run main function
main
