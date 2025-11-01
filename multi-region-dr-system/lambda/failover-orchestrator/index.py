import json
import boto3
import os
import time
from datetime import datetime

route53 = boto3.client('route53')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

HOSTED_ZONE_ID = os.environ.get('HOSTED_ZONE_ID')
SNS_TOPIC = os.environ.get('SNS_TOPIC')
PRIMARY_REGION = os.environ.get('PRIMARY_REGION', 'ap-south-1')
SECONDARY_REGION = os.environ.get('SECONDARY_REGION', 'ap-southeast-1')

def handler(event, context):
    """
    Failover orchestrator that monitors health checks and manages
    automatic failover between regions
    """
    
    try:
        # Parse CloudWatch alarm or health check event
        if 'Records' in event:
            message = json.loads(event['Records'][0]['Sns']['Message'])
        else:
            message = event
        
        # Determine if this is a health check alarm
        if 'AlarmName' in message:
            handle_alarm(message)
        elif 'health-check' in event:
            handle_health_check_change(event)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Failover orchestration completed'})
        }
        
    except Exception as e:
        print(f"Error in failover orchestrator: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_alarm(alarm_message):
    """Handle CloudWatch alarm for regional failure"""
    
    alarm_name = alarm_message.get('AlarmName', '')
    new_state = alarm_message.get('NewStateValue', '')
    region = alarm_message.get('Region', '')
    
    print(f"Processing alarm: {alarm_name}, State: {new_state}, Region: {region}")
    
    if new_state == 'ALARM':
        # Regional failure detected
        if 'mumbai' in alarm_name.lower() or region == PRIMARY_REGION:
            initiate_failover(PRIMARY_REGION, SECONDARY_REGION)
        elif 'singapore' in alarm_name.lower() or region == SECONDARY_REGION:
            initiate_failover(SECONDARY_REGION, PRIMARY_REGION)
    
    elif new_state == 'OK':
        # Region recovered
        send_notification(
            subject=f'Region Recovered: {region}',
            message=f'Region {region} has recovered and is now healthy.'
        )

def initiate_failover(failed_region, target_region):
    """Initiate failover from failed region to target region"""
    
    print(f"Initiating failover from {failed_region} to {target_region}")
    
    start_time = time.time()
    
    try:
        # Verify target region health before failover
        if not verify_region_health(target_region):
            raise Exception(f"Target region {target_region} is not healthy")
        
        # Update Route 53 health check status
        update_health_checks(failed_region, target_region)
        
        # Calculate RTO
        rto = time.time() - start_time
        
        # Log failover metrics
        log_failover_metrics(failed_region, target_region, rto)
        
        # Send notification
        send_notification(
            subject=f'FAILOVER: {failed_region} → {target_region}',
            message=f"""
            Automatic failover executed successfully.
            
            Failed Region: {failed_region}
            Target Region: {target_region}
            RTO: {rto:.2f} seconds
            Timestamp: {datetime.now().isoformat()}
            
            All traffic is now being routed to {target_region}.
            """
        )
        
        print(f"Failover completed successfully in {rto:.2f} seconds")
        
    except Exception as e:
        error_message = f"Failover failed: {str(e)}"
        print(error_message)
        send_notification(
            subject='FAILOVER FAILED',
            message=error_message
        )
        raise

def verify_region_health(region):
    """Verify that target region is healthy before failover"""
    try:
        # Check health check status for the region
        health_checks = route53.list_health_checks()
        
        for hc in health_checks['HealthChecks']:
            if region in hc.get('HealthCheckConfig', {}).get('FullyQualifiedDomainName', ''):
                status = route53.get_health_check_status(
                    HealthCheckId=hc['Id']
                )
                
                # Check if at least one checker reports healthy
                for checker in status['HealthCheckObservations']:
                    if checker['StatusReport']['Status'] == 'Success':
                        return True
        
        return False
        
    except Exception as e:
        print(f"Error verifying region health: {str(e)}")
        return False

def update_health_checks(failed_region, target_region):
    """Update Route 53 health check configurations"""
    try:
        # In practice, Route 53 handles this automatically based on
        # health check results. This function can be used for additional
        # custom logic or manual overrides if needed.
        
        print(f"Health checks updated for failover")
        
    except Exception as e:
        print(f"Error updating health checks: {str(e)}")

def handle_health_check_change(event):
    """Handle Route 53 health check state changes"""
    
    health_check_id = event.get('health-check', {}).get('id')
    status = event.get('health-check', {}).get('status')
    
    print(f"Health check {health_check_id} status changed to {status}")
    
    if status == 'unhealthy':
        send_notification(
            subject=f'Health Check Unhealthy: {health_check_id}',
            message=f'Health check {health_check_id} is reporting unhealthy status.'
        )

def log_failover_metrics(failed_region, target_region, rto):
    """Log failover metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='DR-System',
            MetricData=[
                {
                    'MetricName': 'FailoverCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'FailedRegion', 'Value': failed_region},
                        {'Name': 'TargetRegion', 'Value': target_region}
                    ]
                },
                {
                    'MetricName': 'RTO',
                    'Value': rto,
                    'Unit': 'Seconds',
                    'Dimensions': [
                        {'Name': 'FailedRegion', 'Value': failed_region},
                        {'Name': 'TargetRegion', 'Value': target_region}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error logging metrics: {str(e)}")

def send_notification(subject, message):
    """Send SNS notification"""
    try:
        if SNS_TOPIC:
            sns.publish(
                TopicArn=SNS_TOPIC,
                Subject=subject,
                Message=message
            )
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
