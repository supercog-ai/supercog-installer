import psycopg2
import time
import statistics
from datetime import datetime
import json
import os
from urllib.parse import urlparse
from psycopg2 import pool

class DatabaseBenchmark:
    def __init__(self, database_url, min_connections=1, max_connections=5):
        self.connection_params = self._get_connection_params(database_url)
        self.pool = pool.ThreadedConnectionPool(
            minconn=min_connections,
            maxconn=max_connections,
            **self.connection_params
        )
    
    def _get_connection_params(self, database_url):
        parsed = urlparse(database_url)
        return {
            'dbname': parsed.path[1:],
            'user': parsed.username,
            'password': parsed.password,
            'host': parsed.hostname,
            'port': parsed.port or 5432
        }
    
    def benchmark_new_connections(self, query, iterations=100):
        """Benchmark creating new connections for each query"""
        connect_times = []
        query_times = []
        total_times = []
        
        for _ in range(iterations):
            start_total = time.perf_counter()
            
            # Measure connection time
            start_connect = time.perf_counter()
            conn = psycopg2.connect(**self.connection_params)
            cur = conn.cursor()
            connect_time = time.perf_counter() - start_connect
            connect_times.append(connect_time)
            
            # Measure query execution time
            start_query = time.perf_counter()
            cur.execute(query)
            cur.fetchall()
            query_time = time.perf_counter() - start_query
            query_times.append(query_time)
            
            total_time = time.perf_counter() - start_total
            total_times.append(total_time)
            
            cur.close()
            conn.close()
        
        return self._calculate_stats("New Connection Per Query", connect_times, query_times, total_times, query)
    
    def benchmark_pool(self, query, iterations=100):
        """Benchmark using connection pool"""
        connect_times = []
        query_times = []
        total_times = []
        
        for _ in range(iterations):
            start_total = time.perf_counter()
            
            # Measure connection acquisition time
            start_connect = time.perf_counter()
            conn = self.pool.getconn()
            cur = conn.cursor()
            connect_time = time.perf_counter() - start_connect
            connect_times.append(connect_time)
            
            # Measure query execution time
            start_query = time.perf_counter()
            cur.execute(query)
            cur.fetchall()
            query_time = time.perf_counter() - start_query
            query_times.append(query_time)
            
            total_time = time.perf_counter() - start_total
            total_times.append(total_time)
            
            cur.close()
            self.pool.putconn(conn)
        
        return self._calculate_stats("Connection Pool", connect_times, query_times, total_times, query)
    
    def _calculate_stats(self, method_name, connect_times, query_times, total_times, query):
        return {
            'method': method_name,
            'timestamp': datetime.now().isoformat(),
            'query': query,
            'connection': {
                'min': min(connect_times) * 1000,
                'max': max(connect_times) * 1000,
                'mean': statistics.mean(connect_times) * 1000,
                'median': statistics.median(connect_times) * 1000,
                'stddev': statistics.stdev(connect_times) * 1000
            },
            'query_execution': {
                'min': min(query_times) * 1000,
                'max': max(query_times) * 1000,
                'mean': statistics.mean(query_times) * 1000,
                'median': statistics.median(query_times) * 1000,
                'stddev': statistics.stdev(query_times) * 1000
            },
            'total': {
                'min': min(total_times) * 1000,
                'max': max(total_times) * 1000,
                'mean': statistics.mean(total_times) * 1000,
                'median': statistics.median(total_times) * 1000,
                'stddev': statistics.stdev(total_times) * 1000
            }
        }
    
    def compare_methods(self, query, iterations=100):
        """Compare performance between new connections and connection pool"""
        new_conn_stats = self.benchmark_new_connections(query, iterations)
        pool_stats = self.benchmark_pool(query, iterations)
        
        comparison = {
            'timestamp': datetime.now().isoformat(),
            'iterations': iterations,
            'new_connections': new_conn_stats,
            'connection_pool': pool_stats,
            'improvement': {
                'connection_time': {
                    'mean': (new_conn_stats['connection']['mean'] - pool_stats['connection']['mean']) / new_conn_stats['connection']['mean'] * 100,
                    'median': (new_conn_stats['connection']['median'] - pool_stats['connection']['median']) / new_conn_stats['connection']['median'] * 100
                },
                'total_time': {
                    'mean': (new_conn_stats['total']['mean'] - pool_stats['total']['mean']) / new_conn_stats['total']['mean'] * 100,
                    'median': (new_conn_stats['total']['median'] - pool_stats['total']['median']) / new_conn_stats['total']['median'] * 100
                }
            }
        }
        
        return comparison
    
    def close(self):
        """Close the connection pool"""
        if self.pool:
            self.pool.closeall()

if __name__ == "__main__":
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        raise ValueError("DATABASE_URL environment variable is required")
    
    # Test query
    test_query = "SELECT * FROM agents LIMIT 100"
    
    # Initialize benchmark with a pool of 1-5 connections
    benchmark = DatabaseBenchmark(database_url, min_connections=1, max_connections=5)
    
    try:
        # Run comparison
        results = benchmark.compare_methods(test_query, iterations=100)
        print(json.dumps(results, indent=2))
    finally:
        benchmark.close()
