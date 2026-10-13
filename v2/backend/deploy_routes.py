import os
import re
import subprocess
import hashlib
import hmac
import json
import secrets
import threading
import time
import requests
from flask import Blueprint, request, jsonify

deploy_bp = Blueprint('deploy', __name__)

JENKINS_URL = os.getenv('JENKINS_URL', 'http://localhost:8080').rstrip('/')
JENKINS_USER = os.getenv('JENKINS_USER')
JENKINS_TOKEN = os.getenv('JENKINS_TOKEN')
JOB_NAME = 'deploy-pipeline-v2'
VM2_HOST = os.getenv('VM2_HOST', 'projectvm2@my-app')
APP_BASE_URL = os.getenv('APP_BASE_URL', 'http://localhost:8080').rstrip('/')
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
    mine = owns(name)
    available = free and (mine or not _is_pending(name))
    return jsonify({'status': 'ok', 'available': available, 'owned': mine and not free})


@deploy_bp.route('/deploy', methods=['POST'])
def deploy():
    repo_url = (request.form.get('repo_url') or '').strip()
    app_path = (request.form.get('app_path') or '.').strip()
    template = (request.form.get('template') or '').strip()
    app_name = (request.form.get('app_name') or '').strip()

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
        free = name_is_free(app_name)
    except Exception:
        return bad('Could not check the application name', 500)
    mine = owns(app_name)
    if not free and not mine:
        return bad('This name is already in use, please choose another', 409)
    new_token = None
    if free:
        with _lock:
            if not mine and _is_pending(app_name):
                return bad('This name is being deployed right now, please choose another', 409)
            PENDING[app_name] = time.time()
            if not mine:
                new_token = secrets.token_hex(16)
                d = _load_tokens()
                d[app_name] = _hash(new_token)
                _save_tokens(d)

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
    return jsonify({'status': 'triggered', 'queue_path': m.group(0), 'token': new_token})


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
        live_url = None
        an = request.args.get('app_name', '')
        if status == 'finished' and result == 'SUCCESS' and NAME_RE.match(an):
            live_url = f'{APP_BASE_URL}/apps/{an}/'
        return jsonify({'status': status, 'result': result if status == 'finished' else None,
                        'build_number': num, 'steps': steps, 'reason': reason, 'logs': lines, 'live_url': live_url})
    except requests.exceptions.RequestException:
        return jsonify({'status': 'error', 'message': 'Could not reach Jenkins'}), 502


@deploy_bp.route('/health')
def health():
    name = (request.args.get('name') or '').strip()
    if not NAME_RE.match(name):
        return jsonify({'status': 'error', 'message': 'Invalid name'}), 400
    try:
        r = subprocess.run(
            ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', VM2_HOST,
             'cat', '~/deployforge/health.db'],
            capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        return jsonify({'status': 'error', 'message': 'Health data timed out'}), 504
    if r.returncode != 0:
        return jsonify({'status': 'ok', 'found': False})
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) == 6 and parts[0] == name:
            return jsonify({'status': 'ok', 'found': True, 'health': parts[1],
                            'code': parts[2], 'checked_at': int(parts[3]),
                            'restarts': int(parts[4])})
    return jsonify({'status': 'ok', 'found': False})


def _ssh_cat(path):
    r = subprocess.run(
        ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', VM2_HOST, 'cat', path],
        capture_output=True, text=True, timeout=15)
    return r.stdout if r.returncode == 0 else ''


@deploy_bp.route('/history')
def history():
    try:
        deps = _ssh_cat('~/deployforge/deployments.db')
        hlth = _ssh_cat('~/deployforge/health.db')
    except subprocess.TimeoutExpired:
        return jsonify({'status': 'error', 'message': 'History timed out'}), 504
    health = {}
    for line in hlth.splitlines():
        p = line.split()
        if len(p) == 6:
            health[p[0]] = {'health': p[1], 'code': p[2], 'checked_at': int(p[3])}
    items = []
    for line in deps.splitlines():
        p = line.split()
        if len(p) != 5 or not NAME_RE.match(p[0]):
            continue
        h = health.get(p[0], {})
        items.append({'name': p[0], 'repo': p[1], 'app_path': p[2],
                      'template': None if p[3] == '-' else p[3],
                      'deployed_at': int(p[4]),
                      'health': h.get('health', 'unknown'), 'code': h.get('code'),
                      'live_url': f'{APP_BASE_URL}/apps/{p[0]}/'})
    items.sort(key=lambda x: x['deployed_at'], reverse=True)
    return jsonify({'status': 'ok', 'items': items})


# ---------- token / admin access ----------
TOKEN_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'tokens.json')
ADMIN_KEY = os.getenv('ADMIN_KEY', '')
_lock = threading.Lock()
PENDING = {}


def _is_pending(name):
    t = PENDING.get(name)
    return bool(t) and (time.time() - t) < 900


def _load_tokens():
    try:
        with open(TOKEN_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save_tokens(d):
    os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
    tmp = TOKEN_FILE + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(d, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, TOKEN_FILE)


def _hash(t):
    return hashlib.sha256(t.encode()).hexdigest()


def _same(a, b):
    return hmac.compare_digest(a.encode(), b.encode())


def is_admin():
    k = request.headers.get('X-Admin-Key', '')
    return bool(ADMIN_KEY) and _same(k, ADMIN_KEY)


def owns(name):
    if is_admin():
        return True
    t = request.headers.get('X-Deploy-Token', '')
    h = _load_tokens().get(name)
    return bool(t and h and _same(_hash(t), h))


@deploy_bp.route('/manage', methods=['POST'])
def manage():
    name = (request.form.get('name') or '').strip()
    action = (request.form.get('action') or '').strip()
    if not NAME_RE.match(name) or action not in ('delete', 'restart', 'logs'):
        return jsonify({'status': 'error', 'message': 'Invalid request'}), 400
    try:
        if name_is_free(name):
            return jsonify({'status': 'error', 'message': 'Application not found'}), 404
    except Exception:
        return jsonify({'status': 'error', 'message': 'Could not check the application'}), 500
    if not owns(name):
        return jsonify({'status': 'error', 'message': 'You do not have access to manage this application'}), 403

    d = '~/deployforge/scripts'
    if action == 'delete':
        cmd = (f"bash {d}/assign_port.sh release {name}; docker rm -f {name} >/dev/null 2>&1; "
               f"bash {d}/generate_nginx_route.sh remove {name}; bash {d}/record.sh remove {name}")
    elif action == 'restart':
        cmd = f"docker restart {name}"
    else:
        cmd = f"docker logs --tail 100 {name} 2>&1"
    try:
        r = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', VM2_HOST, cmd],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return jsonify({'status': 'error', 'message': 'Action timed out'}), 504
    if action != 'logs' and r.returncode != 0:
        return jsonify({'status': 'error', 'message': 'Action failed'}), 500
    if action == 'delete':
        with _lock:
            t = _load_tokens()
            t.pop(name, None)
            _save_tokens(t)
            PENDING.pop(name, None)
    if action == 'logs':
        return jsonify({'status': 'ok', 'logs': r.stdout.splitlines()[-100:]})
    return jsonify({'status': 'ok', 'message': 'Done'})
