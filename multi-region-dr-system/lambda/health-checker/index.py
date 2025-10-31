import json
import boto3
import os
import time
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

TABLE_NAME = os.environ['TABLE_NAME']
REGION = os.environ['REGION']
SNS_TOPIC = os.environ['SNS_TOPIC']

def handler(event, context):
    """
    Health checker Lambda function that validates system health
    and reports metrics to CloudWatch
    """
    
    health_status = {
        'timestamp': int(time.time()),
        'region': REGION,
        'checks': {}
    }
    
    try:
        # Check DynamoDB connectivity and latency
        dynamodb_health = check_dynamodb()
        health_status['checks']['dynamodb'] = dynamodb_health
        
        # Publish custom metrics to CloudWatch
        publish_metrics(dynamodb_health)
        
        # Determine overall health
        all_healthy = all(
            check['status'] == 'healthy' 
            for check in health_status['checks'].values()
        )
        
        health_status['overall_status'] = 'healthy' if all_healthy else 'unhealthy'
        
        # Send alert if unhealthy
        if not all_healthy:
            send_alert(health_status)
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_status),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"Health check failed: {str(e)}"
        print(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'message': error_message,
                'region': REGION
            })
        }

def check_dynamodb():
    """Check DynamoDB table health and measure latency"""
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        start_time = time.time()
        response = table.get_item(
            Key={'id': 'health-check'},
            ConsistentRead=True
        )
        latency = (time.time() - start_time) * 1000
        
        return {
            'status': 'healthy',
            'latency_ms': round(latency, 2),
            'table_status': 'active'
        }
        
    except Exception as e:
        return {
            'status': 'unhealthy',
            'error': str(e)
        }

def publish_metrics(dynamodb_health):
    """Publish custom metrics to CloudWatch"""
    try:
        if dynamodb_health['status'] == 'healthy':
            cloudwatch.put_metric_data(
                Namespace='DR-System',
                MetricData=[
                    {
                        'MetricName': 'DynamoDBLatency',
                        'Value': dynamodb_health['latency_ms'],
                        'Unit': 'Milliseconds',
                        'Dimensions': [
                            {
                                'Name': 'Region',
                                'Value': REGION
                            }
                        ]
                    },
                    {
                        'MetricName': 'HealthCheckStatus',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'Region',
                                'Value': REGION
                            }
                        ]
                    }
                ]
            )
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def send_alert(health_status):
    """Send SNS alert for unhealthy status"""
    try:
        message = f"""
        Health Check Alert - {REGION}
        
        Time: {datetime.now().isoformat()}
        Status: {health_status['overall_status']}
        
        Details:
        {json.dumps(health_status['checks'], indent=2)}
        """
        
        sns.publish(
            TopicArn=SNS_TOPIC,
            Subject=f'[ALERT] Health Check Failed - {REGION}',
            Message=message
        )
    except Exception as e:
        print(f"Error sending alert: {str(e)}")
