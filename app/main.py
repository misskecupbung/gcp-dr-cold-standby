"""
Sample app for the DR cold standby lab.
Stateless Flask service that returns instance info - useful for verifying
which region is handling traffic after failover.
"""

from flask import Flask, jsonify, request
import socket
import os
import logging
from datetime import datetime
import json

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

REGION = os.environ.get('REGION', 'unknown')
INSTANCE_NAME = socket.gethostname()
VERSION = os.environ.get('APP_VERSION', '1.0.0')
START_TIME = datetime.utcnow()


def get_instance_metadata():
    """Fetch zone/region info from the GCP metadata server."""
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
    """Health endpoint - LB uses this to check if we're alive."""
    return jsonify({
        'status': 'healthy',
        'hostname': INSTANCE_NAME,
        'timestamp': datetime.utcnow().isoformat(),
        'region': REGION
    }), 200


@app.route('/ready')
def ready():
    """Readiness check - could add DB connectivity tests here if needed."""
    return jsonify({
        'ready': True,
        'hostname': INSTANCE_NAME,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.route('/')
def index():
    """Main endpoint - shows where the request landed."""
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
    """Returns some sample data along with server info."""
    metadata = get_instance_metadata()
    
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
    """Simple echo - returns whatever you POST to it."""
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
    """Extended status info about the running instance."""
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
    """For testing - pass ?fail=true to make this return a 500."""
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
    """Log incoming requests."""
    logger.info(f"Request: {request.method} {request.path} from {request.remote_addr}")


@app.after_request
def add_headers(response):
    """Tag responses with instance info."""
    response.headers['X-Served-By'] = INSTANCE_NAME
    response.headers['X-Region'] = REGION
    return response


@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested resource was not found',
        'served_by': INSTANCE_NAME
    }), 404


@app.errorhandler(500)
def internal_error(error):
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
