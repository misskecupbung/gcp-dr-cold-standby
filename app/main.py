"""
DR Cold Standby Lab - Sample Application
A simple Flask application demonstrating a stateless web service
"""

from flask import Flask, jsonify, request
import socket
import os
import logging
from datetime import datetime
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
REGION = os.environ.get('REGION', 'unknown')
INSTANCE_NAME = socket.gethostname()
VERSION = os.environ.get('APP_VERSION', '1.0.0')
START_TIME = datetime.utcnow()


def get_instance_metadata():
    """Get instance metadata from GCP metadata server"""
    try:
        import urllib.request
        headers = {'Metadata-Flavor': 'Google'}
        
        def fetch_metadata(path):
            url = f"http://metadata.google.internal/computeMetadata/v1/{path}"
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=2) as response:
                return response.read().decode('utf-8')
        
        zone = fetch_metadata('instance/zone').split('/')[-1]
        region = '-'.join(zone.split('-')[:-1])
        instance_id = fetch_metadata('instance/id')
        
        return {
            'zone': zone,
            'region': region,
            'instance_id': instance_id
        }
    except Exception as e:
        logger.warning(f"Could not fetch metadata: {e}")
        return {
            'zone': 'unknown',
            'region': REGION,
            'instance_id': 'unknown'
        }


@app.route('/health')
def health():
    """Health check endpoint for load balancer"""
    return jsonify({
        'status': 'healthy',
        'hostname': INSTANCE_NAME,
        'timestamp': datetime.utcnow().isoformat(),
        'region': REGION
    }), 200


@app.route('/ready')
def ready():
    """Readiness probe endpoint"""
    # Add any readiness checks here (e.g., database connectivity)
    return jsonify({
        'ready': True,
        'hostname': INSTANCE_NAME,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/')
def index():
    """Main application endpoint"""
    metadata = get_instance_metadata()
    uptime = (datetime.utcnow() - START_TIME).total_seconds()
    
    return jsonify({
        'message': 'DR Cold Standby Lab - Application Running',
        'hostname': INSTANCE_NAME,
        'region': metadata['region'],
        'zone': metadata['zone'],
        'instance_id': metadata['instance_id'],
        'version': VERSION,
        'uptime_seconds': round(uptime, 2),
        'timestamp': datetime.utcnow().isoformat()
    })


@app.route('/api/data')
def data():
    """Sample data endpoint"""
    metadata = get_instance_metadata()
    
    # Simulate some application data
    sample_data = {
        'items': [
            {'id': 1, 'name': 'Item 1', 'value': 100},
            {'id': 2, 'name': 'Item 2', 'value': 200},
            {'id': 3, 'name': 'Item 3', 'value': 300},
        ],
        'total': 3,
        'served_by': {
            'hostname': INSTANCE_NAME,
            'region': metadata['region'],
            'zone': metadata['zone']
        },
        'timestamp': datetime.utcnow().isoformat()
    }
    
    return jsonify(sample_data)


@app.route('/api/echo', methods=['POST'])
def echo():
    """Echo endpoint for testing"""
    data = request.get_json() or {}
    metadata = get_instance_metadata()
    
    return jsonify({
        'received': data,
        'served_by': {
            'hostname': INSTANCE_NAME,
            'region': metadata['region']
        },
        'timestamp': datetime.utcnow().isoformat()
    })


@app.route('/api/status')
def status():
    """Detailed status endpoint"""
    metadata = get_instance_metadata()
    uptime = (datetime.utcnow() - START_TIME).total_seconds()
    
    return jsonify({
        'application': {
            'name': 'DR Cold Standby Lab',
            'version': VERSION,
            'uptime_seconds': round(uptime, 2),
            'start_time': START_TIME.isoformat()
        },
        'instance': {
            'hostname': INSTANCE_NAME,
            'region': metadata['region'],
            'zone': metadata['zone'],
            'instance_id': metadata['instance_id']
        },
        'environment': {
            'python_version': os.popen('python3 --version').read().strip(),
            'region_env': REGION
        },
        'timestamp': datetime.utcnow().isoformat()
    })


@app.route('/api/fail')
def simulate_failure():
    """Endpoint to simulate application failure (for testing)"""
    # This can be used to test health check failures
    fail = request.args.get('fail', 'false').lower() == 'true'
    
    if fail:
        logger.warning("Simulated failure triggered!")
        return jsonify({
            'status': 'error',
            'message': 'Simulated failure'
        }), 500
    
    return jsonify({
        'status': 'ok',
        'message': 'Use ?fail=true to simulate failure'
    })


@app.before_request
def log_request():
    """Log incoming requests"""
    logger.info(f"Request: {request.method} {request.path} from {request.remote_addr}")


@app.after_request
def add_headers(response):
    """Add custom headers to response"""
    response.headers['X-Served-By'] = INSTANCE_NAME
    response.headers['X-Region'] = REGION
    return response


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested resource was not found',
        'served_by': INSTANCE_NAME
    }), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error(f"Internal error: {error}")
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An internal error occurred',
        'served_by': INSTANCE_NAME
    }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    debug = os.environ.get('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting application on port {port}")
    logger.info(f"Region: {REGION}, Instance: {INSTANCE_NAME}")
    
    app.run(host='0.0.0.0', port=port, debug=debug)
