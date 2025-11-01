import json
import boto3
import os
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

TABLE_NAME = os.environ['TABLE_NAME']
REGION = os.environ['REGION']

def handler(event, context):
    """
    Main traffic router Lambda function that handles incoming requests
    from ALB and interacts with DynamoDB
    """
    
    try:
        # Parse incoming request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = {}
        
        http_method = event.get('httpMethod', event.get('requestContext', {}).get('http', {}).get('method', 'GET'))
        path = event.get('path', event.get('rawPath', '/'))
        
        # Handle health check endpoint
        if path == '/health':
            return health_check_response()
        
        # Route based on HTTP method
        if http_method == 'GET':
            response = handle_get_request(event, body)
        elif http_method == 'POST':
            response = handle_post_request(event, body)
        elif http_method == 'PUT':
            response = handle_put_request(event, body)
        elif http_method == 'DELETE':
            response = handle_delete_request(event, body)
        else:
            response = {
                'statusCode': 405,
                'body': json.dumps({'error': 'Method not allowed'})
            }
        
        # Add CORS headers
        response['headers'] = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'X-Region': REGION
        }
        
        # Log metrics
        log_request_metrics(http_method, response['statusCode'])
        
        return response
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e),
                'region': REGION
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }

def health_check_response():
    """Return health check response for ALB"""
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'healthy',
            'region': REGION,
            'timestamp': datetime.now().isoformat()
        })
    }

def handle_get_request(event, body):
    """Handle GET requests - retrieve data from DynamoDB"""
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        # Get item ID from query parameters or path
        item_id = event.get('queryStringParameters', {}).get('id') if event.get('queryStringParameters') else None
        
        if item_id:
            # Get specific item
            response = table.get_item(Key={'id': item_id})
            
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'data': response['Item'],
                        'region': REGION
                    }, default=str)
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Item not found'})
                }
        else:
            # Scan table for all items (limited)
            response = table.scan(Limit=100)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'data': response['Items'],
                    'count': len(response['Items']),
                    'region': REGION
                }, default=str)
            }
            
    except Exception as e:
        print(f"Error in GET request: {str(e)}")
        raise

def handle_post_request(event, body):
    """Handle POST requests - create new items in DynamoDB"""
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        # Generate unique ID
        item_id = str(uuid.uuid4())
        
        # Create item with timestamp
        item = {
            'id': item_id,
            'timestamp': int(datetime.now().timestamp()),
            'region': REGION,
            'data': body.get('data', {})
        }
        
        table.put_item(Item=item)
        
        return {
            'statusCode': 201,
            'body': json.dumps({
                'message': 'Item created successfully',
                'id': item_id,
                'region': REGION
            })
        }
        
    except Exception as e:
        print(f"Error in POST request: {str(e)}")
        raise

def handle_put_request(event, body):
    """Handle PUT requests - update existing items"""
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        item_id = body.get('id')
        if not item_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Item ID required'})
            }
        
        # Update item
        response = table.update_item(
            Key={'id': item_id},
            UpdateExpression='SET #data = :data, #timestamp = :timestamp, #region = :region',
            ExpressionAttributeNames={
                '#data': 'data',
                '#timestamp': 'timestamp',
                '#region': 'region'
            },
            ExpressionAttributeValues={
                ':data': body.get('data', {}),
                ':timestamp': int(datetime.now().timestamp()),
                ':region': REGION
            },
            ReturnValues='ALL_NEW'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Item updated successfully',
                'data': response['Attributes'],
                'region': REGION
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in PUT request: {str(e)}")
        raise

def handle_delete_request(event, body):
    """Handle DELETE requests - remove items from DynamoDB"""
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        item_id = event.get('queryStringParameters', {}).get('id') if event.get('queryStringParameters') else body.get('id')
        
        if not item_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Item ID required'})
            }
        
        table.delete_item(Key={'id': item_id})
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Item deleted successfully',
                'id': item_id,
                'region': REGION
            })
        }
        
    except Exception as e:
        print(f"Error in DELETE request: {str(e)}")
        raise

def log_request_metrics(method, status_code):
    """Log custom metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='DR-System',
            MetricData=[
                {
                    'MetricName': 'RequestCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Region', 'Value': REGION},
                        {'Name': 'Method', 'Value': method},
                        {'Name': 'StatusCode', 'Value': str(status_code)}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error logging metrics: {str(e)}")
