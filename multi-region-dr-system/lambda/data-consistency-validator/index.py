import json
import boto3
import os
import time
from datetime import datetime

PRIMARY_REGION = os.environ.get('PRIMARY_REGION', 'ap-south-1')
SECONDARY_REGION = os.environ.get('SECONDARY_REGION', 'ap-southeast-1')
TABLE_NAME = os.environ.get('TABLE_NAME')
SNS_TOPIC = os.environ.get('SNS_TOPIC')

# Initialize DynamoDB clients for both regions
dynamodb_primary = boto3.resource('dynamodb', region_name=PRIMARY_REGION)
dynamodb_secondary = boto3.resource('dynamodb', region_name=SECONDARY_REGION)
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

def handler(event, context):
    """
    Data consistency validator that checks replication status
    and data integrity across regions
    """
    
    try:
        validation_results = {
            'timestamp': datetime.now().isoformat(),
            'primary_region': PRIMARY_REGION,
            'secondary_region': SECONDARY_REGION,
            'checks': {}
        }
        
        # Check replication lag
        replication_lag = check_replication_lag()
        validation_results['checks']['replication_lag'] = replication_lag
        
        # Validate data consistency
        consistency_check = validate_data_consistency()
        validation_results['checks']['data_consistency'] = consistency_check
        
        # Check for conflicts
        conflicts = detect_conflicts()
        validation_results['checks']['conflicts'] = conflicts
        
        # Determine overall status
        validation_results['status'] = determine_overall_status(validation_results['checks'])
        
        # Log metrics
        log_validation_metrics(validation_results)
        
        # Send alert if issues detected
        if validation_results['status'] != 'healthy':
            send_alert(validation_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps(validation_results, default=str)
        }
        
    except Exception as e:
        print(f"Error in data validation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_replication_lag():
    """Measure replication lag between regions"""
    try:
        table_primary = dynamodb_primary.Table(TABLE_NAME)
        
        # Write test item with timestamp
        test_id = f'replication-test-{int(time.time())}'
        write_time = time.time()
        
        table_primary.put_item(
            Item={
                'id': test_id,
                'timestamp': int(write_time),
                'test': True,
                'region': PRIMARY_REGION
            }
        )
        
        # Wait and check in secondary region
        time.sleep(2)
        
        table_secondary = dynamodb_secondary.Table(TABLE_NAME)
        
        max_attempts = 10
        for attempt in range(max_attempts):
            try:
                response = table_secondary.get_item(
                    Key={'id': test_id},
                    ConsistentRead=True
                )
                
                if 'Item' in response:
                    replication_time = time.time()
                    lag = (replication_time - write_time) * 1000
                    
                    # Clean up test item
                    table_primary.delete_item(Key={'id': test_id})
                    table_secondary.delete_item(Key={'id': test_id})
                    
                    return {
                        'status': 'success',
                        'lag_ms': round(lag, 2),
                        'thres
