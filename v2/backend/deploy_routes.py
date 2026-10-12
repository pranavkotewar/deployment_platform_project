import os
import re
import subprocess
import requests
from flask import Blueprint, request, jsonify

deploy_bp = Blueprint('deploy', __name__)

JENKINS_URL = os.getenv('JENKINS_URL', 'http://localhost:8080').rstrip('/')
JENKINS_USER = os.getenv('JENKINS_USER')
JENKINS_TOKEN = os.getenv('JENKINS_TOKEN')
JOB_NAME = 'deploy-pipeline-v2'
VM2_HOST = os.getenv('VM2_HOST', 'projectvm2@my-app')
PORT_SCRIPT = os.path.join(os.path.dirname(__file__), '..', 'scripts', 'assign_port.sh')

REPO_RE = re.compile(r'^https://github\.com/[\w.-]+/[\w.-]+?(\.git)?/?$')
PATH_RE = re.compile(r'^[A-Za-z0-9._/-]+$')
NAME_RE = re.compile(r'^[a-z0-9][a-z0-9-]{0,40}$')
QUEUE_RE = re.compile(r'^/queue/item/[0-9]+/?$')

# Jenkins stage -> dashboard step index
STEP_OF = {
    'Check Parameters': 0, 'Copy Scripts to VM2': 0, 'Clone Repository': 0,
    'Validate': 1,
    'Resolve Dockerfile': 2, 'Build Image': 2,
    'Assign Port': 3, 'Run Container': 3, 'Create Route': 3,
    'Health Check': 4,
}
STEP_NAMES = ['Repository Cloned', 'Validation Passed', 'Docker Image Built',
              'Container Started', 'Health Check']
REASON_RE = re.compile(r'VALIDATION FAILED|HEALTH CHECK FAILED|DeployForge ERROR|^fatal:|Invalid [A-Z_]+|^ERROR: (?!script returned)')


def auth():
    return (JENKINS_USER, JENKINS_TOKEN)


def name_is_free(name):
    with open(PORT_SCRIPT) as script:
        r = subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', VM2_HOST,
             'bash', '-s', '--', 'check', name],
            stdin=script, capture_output=True, text=True, timeout=30)
    out = r.stdout.strip()
    if out == 'AVAILABLE':
        return True
    if out == 'TAKEN':
        return False
    raise RuntimeError('name check failed')


@deploy_bp.route('/check-name')
def check_name():
    name = (request.args.get('name') or '').strip()
    if not NAME_RE.match(name):
        return jsonify({'status': 'error', 'available': False,
                        'message': 'Use lowercase letters, digits and hyphen only'}), 400
    try:
        free = name_is_free(name)
    except Exception:
        return jsonify({'status': 'error', 'message': 'Could not check the name right now'}), 500
    return jsonify({'status': 'ok', 'available': free})


@deploy_bp.route('/deploy', methods=['POST'])
def deploy():
    repo_url = (request.form.get('repo_url') or '').strip()
    app_path = (request.form.get('app_path') or '.').strip()
    template = (request.form.get('template') or '').strip()
    app_name = (request.form.get('app_name') or '').strip()
    allow_existing = request.form.get('allow_existing') == 'true'  # temporary, Step 11 mein token

    def bad(msg, code=400):
        return jsonify({'status': 'error', 'message': msg}), code

    if not REPO_RE.match(repo_url):
        return bad('Invalid repository URL')
    if not PATH_RE.match(app_path) or '..' in app_path or app_path.startswith('/'):
        return bad('Invalid application path')
    if template not in ('', 'static', 'flask', 'node'):
        return bad('Invalid template')
    if not NAME_RE.match(app_name):
        return bad('Invalid application name (lowercase letters, digits, hyphen)')

    try:
        if not allow_existing and not name_is_free(app_name):
            return bad('This name is already in use, please choose another', 409)
    except Exception:
        return bad('Could not check the application name', 500)

    try:
        s = requests.Session()
        s.auth = auth()
        crumb = s.get(f'{JENKINS_URL}/crumbIssuer/api/json', timeout=10)
        crumb.raise_for_status()
        c = crumb.json()
        resp = s.post(
            f'{JENKINS_URL}/job/{JOB_NAME}/buildWithParameters',
            headers={c['crumbRequestField']: c['crumb']},
            params={'REPO_URL': repo_url, 'APP_PATH': app_path,
                    'TEMPLATE': template, 'APP_NAME': app_name},
            timeout=10)
        resp.raise_for_status()
        queue_url = resp.headers.get('Location', '')
    except requests.exceptions.RequestException:
        return bad('Could not reach Jenkins', 502)

    m = re.search(r'/queue/item/[0-9]+/?$', queue_url)
    if not m:
        return bad('Jenkins did not return a queue item', 502)
    return jsonify({'status': 'triggered', 'queue_path': m.group(0)})


def step_states(stages):
    """wfapi stages list -> 5 dashboard steps."""
    groups = [[] for _ in STEP_NAMES]
    for st in stages:
        idx = STEP_OF.get(st.get('name'))
        if idx is not None:
            groups[idx].append(st.get('status'))
    out = []
    for i, name in enumerate(STEP_NAMES):
        sts = groups[i]
        expected = len([k for k, v in STEP_OF.items() if v == i])
        if any(s in ('FAILED', 'ABORTED', 'UNSTABLE') for s in sts):
            state = 'failed'
        elif any(s in ('IN_PROGRESS', 'PAUSED_PENDING_INPUT') for s in sts):
            state = 'running'
        elif len(sts) == expected and all(s == 'SUCCESS' for s in sts):
            state = 'success'
        elif sts and all(s == 'NOT_EXECUTED' for s in sts):
            state = 'skipped'
        else:
            state = 'pending'
        out.append({'name': name, 'state': state})
    seen_fail = False
    for item in out:
        if seen_fail:
            item['state'] = 'skipped'
        elif item['state'] == 'failed':
            seen_fail = True
    return out


def clean_log(text, limit=60):
    lines = [l for l in text.splitlines()
             if l.strip() and not l.startswith('[Pipeline]') and not l.startswith(' > git')]
    return lines[-limit:]


@deploy_bp.route('/deploy-status')
def deploy_status():
    queue_path = request.args.get('queue_path', '')
    if not QUEUE_RE.match(queue_path):
        return jsonify({'status': 'error', 'message': 'Invalid queue reference'}), 400
    try:
        q = requests.get(f'{JENKINS_URL}{queue_path.rstrip("/")}/api/json', auth=auth(), timeout=10)
        q.raise_for_status()
        qd = q.json()
        if qd.get('cancelled'):
            return jsonify({'status': 'finished', 'result': 'ABORTED', 'steps': [],
                            'reason': 'Deployment was cancelled', 'logs': []})
        if 'executable' not in qd:
            return jsonify({'status': 'queued', 'steps': step_states([]), 'logs': []})

        num = qd['executable']['number']
        base = f'{JENKINS_URL}/job/{JOB_NAME}/{num}'
        wf = requests.get(f'{base}/wfapi/describe', auth=auth(), timeout=10)
        wf.raise_for_status()
        wd = wf.json()
        steps = step_states(wd.get('stages', []))

        log = requests.get(f'{base}/consoleText', auth=auth(), timeout=10)
        full = clean_log(log.text if log.ok else '', limit=100000)
        lines = full[-60:]

        status = 'finished' if wd.get('status') in ('SUCCESS', 'FAILED', 'ABORTED', 'UNSTABLE') else 'running'
        result = wd.get('status')  # SUCCESS / FAILED / ABORTED ...
        reason = None
        if status == 'finished' and result != 'SUCCESS':
            for l in reversed(full):
                if REASON_RE.search(l):
                    reason = l.strip()
                    break
            reason = reason or 'Deployment failed, see the logs'
        return jsonify({'status': status, 'result': result if status == 'finished' else None,
                        'build_number': num, 'steps': steps, 'reason': reason, 'logs': lines})
    except requests.exceptions.RequestException:
        return jsonify({'status': 'error', 'message': 'Could not reach Jenkins'}), 502
