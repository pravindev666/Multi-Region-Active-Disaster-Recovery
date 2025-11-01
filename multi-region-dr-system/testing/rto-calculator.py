#!/usr/bin/env python3
"""
RTO (Recovery Time Objective) Calculator
Measures actual recovery time from failure detection to full service restoration
"""

import boto3
import time
import requests
import argparse
from datetime import datetime
from statistics import mean, median

class RTOCalculator:
    def __init__(self, primary_endpoint, secondary_endpoint, primary_region, secondary_region):
        self.primary_endpoint = primary_endpoint
        self.secondary_endpoint = secondary_endpoint
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.route53 = boto3.client('route53')
        self.cloudwatch_primary = boto3.client('cloudwatch', region_name=primary_region)
        self.cloudwatch_secondary = boto3.client('cloudwatch', region_name=secondary_region)
        
    def measure_endpoint_response_time(self, endpoint, timeout=5):
        """Measure response time for an endpoint"""
        try:
            start = time.time()
            response = requests.get(f"https://{endpoint}/health", timeout=timeout)
            end = time.time()
            
            if response.status_code == 200:
                return {
                    'success': True,
                    'response_time': (end - start) * 1000,
                    'status_code': response.status_code
                }
            else:
                return {
                    'success': False,
                    'response_time': None,
                    'status_code': response.status_code
                }
        except Exception as e:
            return {
                'success': False,
                'response_time': None,
                'error': str(e)
            }
    
    def simulate_failure_and_measure_rto(self):
        """Simulate failure and measure RTO"""
        print("=" * 70)
        print("RTO Measurement Test")
        print("=" * 70)
        
        # Step 1: Verify both endpoints are healthy
        print("\n[1/5] Verifying baseline health...")
        primary_health = self.measure_endpoint_response_time(self.primary_endpoint)
        secondary_health = self.measure_endpoint_response_time(self.secondary_endpoint)
        
        print(f"  Primary ({self.primary_region}): {primary_health}")
        print(f"  Secondary ({self.secondary_region}): {secondary_health}")
        
        if not (primary_health['success'] and secondary_health['success']):
            print("\n  ERROR: Both regions must be healthy before testing")
            return None
        
        # Step 2: Simulate primary region failure
        print("\n[2/5] Simulating primary region failure...")
        print("  NOTE: You need to manually disable the primary region ALB or Lambda")
        print("  Press Enter after disabling the primary region...")
        input()
        
        failure_start_time = time.time()
        
        # Step 3: Monitor until failover completes
        print("\n[3/5] Monitoring failover process...")
        
        failover_detected = False
        service_restored = False
        consecutive_successes = 0
        required_successes = 3
        
        max_wait = 300
        check_interval = 5
        
        while time.time() - failure_start_time < max_wait:
            elapsed = time.time() - failure_start_time
            
            # Check primary endpoint
            primary_check = self.measure_endpoint_response_time(self.primary_endpoint, timeout=3)
            
            # Check secondary endpoint
            secondary_check = self.measure_endpoint_response_time(self.secondary_endpoint, timeout=3)
            
            print(f"\n  Elapsed: {elapsed:.1f}s")
            print(f"    Primary: {'UP' if primary_check['success'] else 'DOWN'}")
            print(f"    Secondary: {'UP' if secondary_check['success'] else 'DOWN'}")
            
            # Detect when primary fails
            if not primary_check['success'] and not failover_detected:
                failover_detected = True
                print(f"  >> Failure detected at {elapsed:.1f}s")
            
            # Detect when service is restored (via secondary)
            if failover_detected and secondary_check['success']:
                consecutive_successes += 1
                print(f"  >> Service responding ({consecutive_successes}/{required_successes})")
                
                if consecutive_successes >= required_successes:
                    service_restored = True
                    rto = time.time() - failure_start_time
                    print(f"\n  >> Service fully restored at {rto:.1f}s")
                    break
            else:
                consecutive_successes = 0
            
            time.sleep(check_interval)
        
        if not service_restored:
            print("\n  ERROR: Service did not restore within timeout")
            return None
        
        # Step 4: Measure performance metrics
        print("\n[4/5] Measuring post-failover performance...")
        
        response_times = []
        for i in range(10):
            result = self.measure_endpoint_response_time(self.secondary_endpoint)
            if result['success']:
                response_times.append(result['response_time'])
            time.sleep(1)
        
        avg_response_time = mean(response_times) if response_times else None
        median_response_time = median(response_times) if response_times else None
        
        print(f"  Average response time: {avg_response_time:.2f}ms")
        print(f"  Median response time: {median_response_time:.2f}ms")
        
        # Step 5: Generate report
        print("\n[5/5] Generating RTO report...")
        
        report = {
            'test_timestamp': datetime.now().isoformat(),
            'rto_seconds': round(rto, 2),
            'rto_target': 60,
            'status': 'PASS' if rto <= 60 else 'FAIL',
            'primary_region': self.primary_region,
            'secondary_region': self.secondary_region,
            'post_failover_performance': {
                'average_response_time_ms': round(avg_response_time, 2) if avg_response_time else None,
                'median_response_time_ms': round(median_response_time, 2) if median_response_time else None,
                'samples': len(response_times)
            }
        }
        
        return report
    
    def get_historical_metrics(self):
        """Get historical RTO metrics from CloudWatch"""
        print("\n" + "=" * 70)
        print("Historical RTO Metrics")
        print("=" * 70)
        
        try:
            end_time = datetime.now()
            start_time = datetime.now().timestamp() - (7 * 24 * 60 * 60)
            
            response = self.cloudwatch_primary.get_metric_statistics(
                Namespace='DR-System',
                MetricName='RTO',
                StartTime=start_time,
                EndTime=end_time.timestamp(),
                Period=3600,
                Statistics=['Average', 'Maximum', 'Minimum']
            )
            
            if response['Datapoints']:
                datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
                
                print(f"\n  Found {len(datapoints)} historical RTO measurements:")
                print("\n  Timestamp                  | Avg RTO | Min RTO | Max RTO")
                print("  " + "-" * 66)
                
                for dp in datapoints:
                    timestamp = dp['Timestamp'].strftime('%Y-%m-%d %H:%M:%S')
                    avg = dp.get('Average', 0)
                    min_val = dp.get('Minimum', 0)
                    max_val = dp.get('Maximum', 0)
                    
                    print(f"  {timestamp} | {avg:7.2f}s | {min_val:7.2f}s | {max_val:7.2f}s")
                
                # Calculate overall statistics
                all_avg = [dp.get('Average', 0) for dp in datapoints]
                overall_avg = mean(all_avg)
                
                print(f"\n  Overall Average RTO: {overall_avg:.2f} seconds")
            else:
                print("\n  No historical RTO data found")
                
        except Exception as e:
            print(f"\n  Error retrieving historical metrics: {str(e)}")
    
    def print_report(self, report):
        """Print formatted RTO report"""
        print("\n" + "=" * 70)
        print("RTO TEST REPORT")
        print("=" * 70)
        
        print(f"\nTest Timestamp: {report['test_timestamp']}")
        print(f"\nRecovery Time Objective (RTO):")
        print(f"  Measured RTO: {report['rto_seconds']} seconds")
        print(f"  Target RTO:   {report['rto_target']} seconds")
        print(f"  Status:       {report['status']}")
        
        if report['status'] == 'PASS':
            print(f"  Result:       RTO target achieved! ({report['rto_seconds']}s < {report['rto_target']}s)")
        else:
            print(f"  Result:       RTO target NOT met ({report['rto_seconds']}s > {report['rto_target']}s)")
        
        print(f"\nRegions:")
        print(f"  Primary:   {report['primary_region']}")
        print(f"  Secondary: {report['secondary_region']}")
        
        perf = report['post_failover_performance']
        if perf['average_response_time_ms']:
            print(f"\nPost-Failover Performance:")
            print(f"  Average Response Time: {perf['average_response_time_ms']:.2f}ms")
            print(f"  Median Response Time:  {perf['median_response_time_ms']:.2f}ms")
            print(f"  Samples Collected:     {perf['samples']}")
        
        print("\n" + "=" * 70)

def main():
    parser = argparse.ArgumentParser(description='Calculate RTO for DR System')
    parser.add_argument('--primary-endpoint', required=True, help='Primary endpoint URL')
    parser.add_argument('--secondary-endpoint', required=True, help='Secondary endpoint URL')
    parser.add_argument('--primary-region', default='ap-south-1', help='Primary AWS region')
    parser.add_argument('--secondary-region', default='ap-southeast-1', help='Secondary AWS region')
    parser.add_argument('--test-failover', action='store_true', help='Run failover test')
    parser.add_argument('--historical', action='store_true', help='Show historical metrics')
    
    args = parser.parse_args()
    
    calculator = RTOCalculator(
        args.primary_endpoint,
        args.secondary_endpoint,
        args.primary_region,
        args.secondary_region
    )
    
    if args.test_failover:
        report = calculator.simulate_failure_and_measure_rto()
        if report:
            calculator.print_report(report)
    
    if args.historical:
        calculator.get_historical_metrics()
    
    if not args.test_failover and not args.historical:
        print("Please specify --test-failover or --historical")
        print("Example: python rto-calculator.py --primary-endpoint api.example.com --secondary-endpoint api.example.com --test-failover")

if __name__ == '__main__':
    main()

#pip3 install boto3 requests
