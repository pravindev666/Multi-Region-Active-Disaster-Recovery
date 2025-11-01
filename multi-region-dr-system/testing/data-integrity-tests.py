#!/usr/bin/env python3
"""
Data Integrity Tests for Multi-Region DR System
Validates data consistency and replication between regions
"""

import boto3
import time
import uuid
import argparse
from datetime import datetime
from statistics import mean

class DataIntegrityTester:
    def __init__(self, table_name, primary_region, secondary_region):
        self.table_name = table_name
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        
        self.dynamodb_primary = boto3.resource('dynamodb', region_name=primary_region)
        self.dynamodb_secondary = boto3.resource('dynamodb', region_name=secondary_region)
        
        self.table_primary = self.dynamodb_primary.Table(table_name)
        self.table_secondary = self.dynamodb_secondary.Table(table_name)
        
    def test_write_replication(self, num_items=10):
        """Test write operations and replication"""
        print("\n" + "=" * 70)
        print("Test 1: Write Replication")
        print("=" * 70)
        
        test_items = []
        replication_times = []
        
        for i in range(num_items):
            item_id = f"test-{uuid.uuid4()}"
            test_data = {
                'id': item_id,
                'timestamp': int(time.time()),
                'test_number': i,
                'data': f'Test data item {i}',
                'region': self.primary_region
            }
            
            # Write to primary
            write_start = time.time()
            self.table_primary.put_item(Item=test_data)
            write_time = (time.time() - write_start) * 1000
            
            print(f"\n  [{i+1}/{num_items}] Written to primary: {item_id}")
            print(f"    Write time: {write_time:.2f}ms")
            
            # Wait for replication
            replication_start = time.time()
            replicated = False
            max_wait = 10
            
            while time.time() - replication_start < max_wait:
                try:
                    response = self.table_secondary.get_item(
                        Key={'id': item_id},
                        ConsistentRead=True
                    )
                    
                    if 'Item' in response:
                        replication_time = (time.time() - replication_start) * 1000
                        replication_times.append(replication_time)
                        replicated = True
                        print(f"    Replicated in: {replication_time:.2f}ms")
                        
                        # Verify data integrity
                        if response['Item'] == test_data:
                            print(f"    Data integrity: PASS")
                        else:
                            print(f"    Data integrity: FAIL - Data mismatch")
                        break
                except:
                    pass
                
                time.sleep(0.1)
            
            if not replicated:
                print(f"    Replication: TIMEOUT (>{max_wait}s)")
            
            test_items.append(item_id)
            time.sleep(0.5)
        
        # Cleanup
        print(f"\n  Cleaning up test items...")
        for item_id in test_items:
            self.table_primary.delete_item(Key={'id': item_id})
            self.table_secondary.delete_item(Key={'id': item_id})
        
        # Results
        print(f"\n  Results:")
        print(f"    Items tested: {num_items}")
        print(f"    Successfully replicated: {len(replication_times)}/{num_items}")
        
        if replication_times:
            avg_replication = mean(replication_times)
            max_replication = max(replication_times)
            min_replication = min(replication_times)
            
            print(f"    Average replication time: {avg_replication:.2f}ms")
            print(f"    Min replication time: {min_replication:.2f}ms")
            print(f"    Max replication time: {max_replication:.2f}ms")
            
            return {
                'test': 'write_replication',
                'status': 'PASS' if avg_replication < 5000 else 'FAIL',
                'items_tested': num_items,
                'replicated': len(replication_times),
                'avg_replication_ms': round(avg_replication, 2),
                'max_replication_ms': round(max_replication, 2)
            }
        else:
            return {
                'test': 'write_replication',
                'status': 'FAIL',
                'items_tested': num_items,
                'replicated': 0
            }
    
    def test_bi_directional_replication(self):
        """Test bi-directional replication"""
        print("\n" + "=" * 70)
        print("Test 2: Bi-directional Replication")
        print("=" * 70)
        
        # Write to primary
        primary_item_id = f"primary-{uuid.uuid4()}"
        primary_data = {
            'id': primary_item_id,
            'timestamp': int(time.time()),
            'origin': 'primary',
            'data': 'Written from primary region'
        }
        
        print(f"\n  Writing to primary region ({self.primary_region})...")
        self.table_primary.put_item(Item=primary_data)
        
        # Wait and verify in secondary
        time.sleep(2)
        response = self.table_secondary.get_item(Key={'id': primary_item_id})
        primary_replicated = 'Item' in response
        
        print(f"    Replicated to secondary: {'YES' if primary_replicated else 'NO'}")
        
        # Write to secondary
        secondary_item_id = f"secondary-{uuid.uuid4()}"
        secondary_data = {
            'id': secondary_item_id,
            'timestamp': int(time.time()),
            'origin': 'secondary',
            'data': 'Written from secondary region'
        }
        
        print(f"\n  Writing to secondary region ({self.secondary_region})...")
        self.table_secondary.put_item(Item=secondary_data)
        
        # Wait and verify in primary
        time.sleep(2)
        response = self.table_primary.get_item(Key={'id': secondary_item_id})
        secondary_replicated = 'Item' in response
        
        print(f"    Replicated to primary: {'YES' if secondary_replicated else 'NO'}")
        
        # Cleanup
        self.table_primary.delete_item(Key={'id': primary_item_id})
        self.table_secondary.delete_item(Key={'id': secondary_item_id})
        
        status = 'PASS' if (primary_replicated and secondary_replicated) else 'FAIL'
        
        print(f"\n  Result: {status}")
        
        return {
            'test': 'bi_directional_replication',
            'status': status,
            'primary_to_secondary': primary_replicated,
            'secondary_to_primary': secondary_replicated
        }
    
    def test_concurrent_writes(self, num_concurrent=5):
        """Test concurrent writes to both regions"""
        print("\n" + "=" * 70)
        print("Test 3: Concurrent Writes (Conflict Resolution)")
        print("=" * 70)
        
        base_id = f"concurrent-{uuid.uuid4()}"
        
        print(f"\n  Writing same ID to both regions simultaneously...")
        
        # Write to both regions at nearly the same time
        primary_data = {
            'id': base_id,
            'timestamp': int(time.time()),
            'source': 'primary',
            'value': 100
        }
        
        secondary_data = {
            'id': base_id,
            'timestamp': int(time.time()),
            'source': 'secondary',
            'value': 200
        }
        
        self.table_primary.put_item(Item=primary_data)
        time.sleep(0.1)
        self.table_secondary.put_item(Item=secondary_data)
        
        # Wait for replication to settle
        print(f"  Waiting for replication to settle...")
        time.sleep(5)
        
        # Check final state in both regions
        primary_result = self.table_primary.get_item(Key={'id': base_id})
        secondary_result = self.table_secondary.get_item(Key={'id': base_id})
        
        print(f"\n  Final state in primary: {primary_result.get('Item', {}).get('source')}")
        print(f"  Final state in secondary: {secondary_result.get('Item', {}).get('source')}")
        
        # Check if both regions converged to same state
        converged = (primary_result.get('Item') == secondary_result.get('Item'))
        
        print(f"\n  Regions converged: {'YES' if converged else 'NO'}")
        
        # Cleanup
        self.table_primary.delete_item(Key={'id': base_id})
        
        return {
            'test': 'concurrent_writes',
            'status': 'PASS' if converged else 'FAIL',
            'converged': converged
        }
    
    def test_read_consistency(self, num_reads=10):
        """Test read consistency across regions"""
        print("\n" + "=" * 70)
        print("Test 4: Read Consistency")
        print("=" * 70)
        
        # Write test item
        item_id = f"read-test-{uuid.uuid4()}"
        test_data = {
            'id': item_id,
            'timestamp': int(time.time()),
            'data': 'Consistency test data'
        }
        
        print(f"\n  Writing test item to primary...")
        self.table_primary.put_item(Item=test_data)
        
        # Wait for replication
        time.sleep(2)
        
        # Perform multiple reads from both regions
        print(f"\n  Performing {num_reads} reads from each region...")
        
        primary_reads = []
        secondary_reads = []
        
        for i in range(num_reads):
            # Read from primary
            try:
                p_response = self.table_primary.get_item(
                    Key={'id': item_id},
                    ConsistentRead=True
                )
                primary_reads.append('Item' in p_response)
            except:
                primary_reads.append(False)
            
            # Read from secondary
            try:
                s_response = self.table_secondary.get_item(
                    Key={'id': item_id},
                    ConsistentRead=True
                )
                secondary_reads.append('Item' in s_response)
            except:
                secondary_reads.append(False)
            
            time.sleep(0.1)
        
        primary_success_rate = (sum(primary_reads) / num_reads) * 100
        secondary_success_rate = (sum(secondary_reads) / num_reads) * 100
        
        print(f"\n  Primary read success rate: {primary_success_rate:.1f}%")
        print(f"  Secondary read success rate: {secondary_success_rate:.1f}%")
        
        # Cleanup
        self.table_primary.delete_item(Key={'id': item_id})
        
        status = 'PASS' if (primary_success_rate == 100 and secondary_success_rate >= 90) else 'FAIL'
        
        print(f"\n  Result: {status}")
        
        return {
            'test': 'read_consistency',
            'status': status,
            'primary_success_rate': primary_success_rate,
            'secondary_success_rate': secondary_success_rate
        }
    
    def run_all_tests(self):
        """Run all data integrity tests"""
        print("\n" + "=" * 70)
        print("DATA INTEGRITY TEST SUITE")
        print(f"Table: {self.table_name}")
        print(f"Primary Region: {self.primary_region}")
        print(f"Secondary Region: {self.secondary_region}")
        print("=" * 70)
        
        results = []
        
        # Test 1: Write Replication
        results.append(self.test_write_replication(num_items=5))
        
        # Test 2: Bi-directional Replication
        results.append(self.test_bi_directional_replication())
        
        # Test 3: Concurrent Writes
        results.append(self.test_concurrent_writes())
        
        # Test 4: Read Consistency
        results.append(self.test_read_consistency(num_reads=10))
        
        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY")
        print("=" * 70)
        
        for result in results:
            status_symbol = "✓" if result['status'] == 'PASS' else "✗"
            print(f"\n  {status_symbol} {result['test'].replace('_', ' ').title()}: {result['status']}")
            
            for key, value in result.items():
                if key not in ['test', 'status']:
                    print(f"      {key}: {value}")
        
        total_tests = len(results)
        passed_tests = sum(1 for r in results if r['status'] == 'PASS')
        
        print(f"\n  Overall: {passed_tests}/{total_tests} tests passed")
        print("=" * 70)
        
        return results

def main():
    parser = argparse.ArgumentParser(description='Data Integrity Tests for DR System')
    parser.add_argument('--table-name', default='dr-application-data', help='DynamoDB table name')
    parser.add_argument('--primary-region', default='ap-south-1', help='Primary AWS region')
    parser.add_argument('--secondary-region', default='ap-southeast-1', help='Secondary AWS region')
    
    args = parser.parse_args()
    
    tester = DataIntegrityTester(
        args.table_name,
        args.primary_region,
        args.secondary_region
    )
    
    tester.run_all_tests()

if __name__ == '__main__':
    main()
