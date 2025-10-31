#!/usr/bin/env python3
"""
Chaos Engineering Script for Multi-Region DR System
Simulates regional failures and measures system resilience
"""

import boto3
import time
import argparse
import json
from datetime import datetime

class ChaosEngineer:
    def __init__(self, region):
        self.region = region
        self.elbv2 = boto3.client('elbv2', region_name=region)
        self.route53 = boto3.client('route53')
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        
    def simulate_alb_failure(self, alb_name):
        """Simulate ALB failure by deregistering all targets"""
        print(f"[{datetime.now()}] Simulating ALB failure in {self.region}")
        
        try:
            # Get ALB ARN
            albs = self.elbv2.describe_load_balancers(Names=[alb_name])
            alb_arn = albs['LoadBalancers'][0]['LoadBalancerArn']
            
            # Get target groups
            target_groups = self.elbv2.describe_target_groups(
                LoadBalancerArn=alb_arn
            )
            
            deregistered_targets = []
            
            for tg in target_groups['TargetGroups']:
                tg_arn = tg['TargetGroupArn']
                
                # Get current targets
                targets = self.elbv2.describe_target_health(
                    TargetGroupArn=tg_arn
                )
                
                # Deregister all targets
                for target in targets['TargetHealthDescriptions']:
                    target_id = target['Target']['Id']
                    
                    self.elbv2.deregister_targets(
                        TargetGroupArn=tg_arn,
                        Targets=[{'Id': target_id}]
                    )
                    
                    deregistered_targets.append({
                        'target_group': tg_arn,
                        'target_id': target_id
                    })
                    
                    print(f"  Deregistered target: {target_id}")
            
            return deregistered_targets
            
        except Exception as e:
            print(f"Error simulating ALB failure: {str(e)}")
            return []
    
    def restore_alb(self, deregistered_targets):
        """Restore ALB by re-registering targets"""
        print(f"[{datetime.now()}] Restoring ALB in {self.region}")
        
        try:
            for target_info in deregistered_targets:
                self.elbv2.register_targets(
                    TargetGroupArn=target_info['target_group'],
                    Targets=[{'Id': target_info['target_id']}]
                )
                print(f"  Re-registered target: {target_info['target_id']}")
                
        except Exception as e:
            print(f"Error restoring ALB: {str(e)}")
    
    def measure_failover_time(self, endpoint, max_wait=300):
        """Measure time until failover completes"""
        import requests
        
        print(f"[{datetime.now()}] Measuring failover time...")
        
        start_time = time.time()
        consecutive_successes = 0
        required_successes = 3
        
        while time.time() - start_time < max_wait:
            try:
                response = requests.get(f"https://{endpoint}/health", timeout=5)
                
                if response.status_code == 200:
                    consecutive_successes += 1
                    print(f"  Health check successful ({consecutive_successes}/{required_successes})")
                    
                    if consecutive_successes >= required_successes:
                        failover_time = time.time() - start_time
                        print(f"\n  Failover completed in {failover_time:.2f} seconds")
                        return failover_time
                else:
                    consecutive_successes = 0
                    
            except Exception as e:
                consecutive_successes = 0
                print(f"  Health check failed: {str(e)}")
            
            time.sleep(5)
        
        print("  Failover did not complete within timeout")
        return None
    
    def inject_latency(self, lambda_name, latency_ms):
        """Inject artificial latency into Lambda function"""
        print(f"[{datetime.now()}] Injecting {latency_ms}ms latency into {lambda_name}")
        
        lambda_client = boto3.client('lambda', region_name=self.region)
        
        try:
            # Get current environment variables
            config = lambda_client.get_function_configuration(
                FunctionName=lambda_name
            )
            
            env_vars = config.get('Environment', {}).get('Variables', {})
            env_vars['CHAOS_LATENCY_MS'] = str(latency_ms)
            
            # Update function with latency injection
            lambda_client.update_function_configuration(
                FunctionName=lambda_name,
                Environment={'Variables': env_vars}
            )
            
            print(f"  Latency injected successfully")
            
        except Exception as e:
            print(f"Error injecting latency: {str(e)}")
    
    def simulate_dynamodb_throttling(self, table_name):
        """Simulate DynamoDB throttling by making rapid requests"""
        print(f"[{datetime.now()}] Simulating DynamoDB throttling")
        
        dynamodb = boto3.resource('dynamodb', region_name=self.region)
        table = dynamodb.Table(table_name)
        
        throttle_count = 0
        
        try:
            # Make rapid requests to trigger throttling
            for i in range(100):
                try:
                    table.get_item(Key={'id': f'chaos-test-{i}'})
                except Exception as e:
                    if 'ProvisionedThroughputExceededException' in str(e):
                        throttle_count += 1
            
            print(f"  Throttled requests: {throttle_count}")
            
        except Exception as e:
            print(f"Error simulating throttling: {str(e)}")
    
    def collect_metrics(self):
        """Collect and display system metrics"""
        print(f"\n[{datetime.now()}] Collecting metrics...")
        
        metrics = {
            'lambda_errors': self.get_lambda_errors(),
            'alb_unhealthy_targets': self.get_unhealthy_targets(),
            'dynamodb_throttles': self.get_dynamodb_throttles()
        }
        
        print(f"\nMetrics Summary:")
        print(f"  Lambda Errors: {metrics['lambda_errors']}")
        print(f"  Unhealthy Targets: {metrics['alb_unhealthy_targets']}")
        print(f"  DynamoDB Throttles: {metrics['dynamodb_throttles']}")
        
        return metrics
    
    def get_lambda_errors(self):
        """Get Lambda error count"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/Lambda',
                MetricName='Errors',
                StartTime=datetime.now().timestamp() - 300,
                EndTime=datetime.now().timestamp(),
                Period=300,
                Statistics=['Sum']
            )
            
            if response['Datapoints']:
                return response['Datapoints'][0]['Sum']
            return 0
            
        except Exception as e:
            print(f"Error getting Lambda metrics: {str(e)}")
            return 0
    
    def get_unhealthy_targets(self):
        """Get unhealthy target count"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/ApplicationELB',
                MetricName='UnHealthyHostCount',
                StartTime=datetime.now().timestamp() - 300,
                EndTime=datetime.now().timestamp(),
                Period=300,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                return response['Datapoints'][0]['Average']
            return 0
            
        except Exception as e:
            print(f"Error getting ALB metrics: {str(e)}")
            return 0
    
    def get_dynamodb_throttles(self):
        """Get DynamoDB throttle count"""
        try:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/DynamoDB',
                MetricName='UserErrors',
                StartTime=datetime.now().timestamp() - 300,
                EndTime=datetime.now().timestamp(),
                Period=300,
                Statistics=['Sum']
            )
            
            if response['Datapoints']:
                return response['Datapoints'][0]['Sum']
            return 0
            
        except Exception as e:
            print(f"Error getting DynamoDB metrics: {str(e)}")
            return 0

def main():
    parser = argparse.ArgumentParser(description='Chaos Engineering for DR System')
    parser.add_argument('--region', required=True, help='AWS region to target')
    parser.add_argument('--alb-name', help='ALB name to simulate failure')
    parser.add_argument('--endpoint', help='Endpoint to monitor')
    parser.add_argument('--restore-after', type=int, default=120, help='Seconds before restoring')
    parser.add_argument('--simulate-failure', action='store_true', help='Simulate ALB failure')
    
    args = parser.parse_args()
    
    chaos = ChaosEngineer(args.region)
    
    print("=" * 60)
    print("Multi-Region DR System - Chaos Engineering Test")
    print("=" * 60)
    
    if args.simulate_failure and args.alb_name:
        # Collect baseline metrics
        print("\nBaseline Metrics:")
        baseline = chaos.collect_metrics()
        
        # Simulate failure
        deregistered = chaos.simulate_alb_failure(args.alb_name)
        
        if args.endpoint:
            # Measure failover time
            failover_time = chaos.measure_failover_time(args.endpoint)
            
            if failover_time:
                print(f"\nRTO Achieved: {failover_time:.2f} seconds")
        
        # Wait before restoring
        print(f"\nWaiting {args.restore_after} seconds before restoration...")
        time.sleep(args.restore_after)
        
        # Restore service
        chaos.restore_alb(deregistered)
        
        # Wait for restoration
        time.sleep(30)
        
        # Collect post-test metrics
        print("\nPost-Test Metrics:")
        post_test = chaos.collect_metrics()
        
        # Generate report
        print("\n" + "=" * 60)
        print("Chaos Engineering Test Complete")
        print("=" * 60)
        
        if failover_time:
            print(f"RTO: {failover_time:.2f} seconds")
            print(f"Target RTO: 60 seconds")
            print(f"Status: {'PASS' if failover_time < 60 else 'FAIL'}")
    else:
        print("\nNo chaos scenario specified. Use --simulate-failure with --alb-name")
        print("Example: python chaos-engineering.py --region ap-south-1 --alb-name mumbai-alb --endpoint api.example.com --simulate-failure")

if __name__ == '__main__':
    main()
