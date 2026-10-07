import os
import re
import json
import uuid
import subprocess
from flask import Blueprint, request, jsonify

detect_bp = Blueprint('detect', __name__)

VM2_HOST = os.getenv('VM2_HOST', 'projectvm2@my-app')
SCRIPT = os.path.join(os.path.dirname(__file__), '..', 'scripts', 'detect_apps.sh')

# Only github https URL allowed (to prevent from command injection)
REPO_RE = re.compile(r'^https://github\.com/[\w.-]+/[\w.-]+?(\.git)?/?$')


@detect_bp.route('/detect', methods=['POST'])
def detect():
    repo_url = (request.form.get('repo_url') or '').strip()

    if not REPO_RE.match(repo_url):
        return jsonify({'status': 'error',
                        'message': 'Please enter a valid GitHub repository URL (https://github.com/user/repo)'}), 400

    work = f'/tmp/detect-{uuid.uuid4().hex[:8]}'
    remote_cmd = (
        f"git clone --depth 1 {repo_url} {work}/repo >/dev/null 2>&1 "
        f"&& bash -s {work}/repo; rc=$?; rm -rf {work}; exit $rc"
    )

    try:
        with open (SCRIPT) as script:
            result = subprocess.run(
                ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', VM2_HOST, remote_cmd],
                stdin=script, capture_output=True, text=True, timeout=60
            )
    except subprocess.TimeoutExpired:
        return jsonify({'status': 'error', 'message': 'Repository scan timed out'}), 504

    if result.returncode !=0 or not result.stdout.strip():
        return jsonify({'status': 'error',
                        'message': 'Could not clone the repository. Check that the URL is correct and the repo is public.'}), 422


    try:
        apps = json.loads(result.stdout)
    except json.JSONDecodeError:
        return jsonify({'status': 'error', 'message': 'Scan produced invalid output'}), 500

    return jsonify({'status': 'ok', 'apps': apps})
