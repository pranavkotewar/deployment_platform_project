import os
import requests
from flask import Flask, request, jsonify, render_template
from dotenv import load_dotenv

#load .env file from project root
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '..', '.env'))

app = Flask(__name__)

JENKINS_URL = os.getenv('JENKINS_URL', 'http://localhost:8080')
JENKINS_USER = os.getenv('JENKINS_USER')
JENKINS_TOKEN = os.getenv('JENKINS_TOKEN')
JOB_NAME = 'deploy-pipeline'
APP_LIVE_URL = 'http://192.168.42.7:9000'

@app.route('/')
def home():
    return render_template('dashboard.html')


@app.route('/deploy', methods=['POST'])
def deploy():
    repo_url = request.form.get('repo_url')

    if not repo_url:
        return jsonify({
            'status': 'error',
            'message': 'Repo URL is required'
        }), 400

    try:
        # Step 1: Get CSRF crumb from Jenkins
        crumb_resp = requests.get(
            f'{JENKINS_URL}/crumbIssuer/api/json',
            auth=(JENKINS_USER, JENKINS_TOKEN)
        )
        crumb_resp.raise_for_status()
        crumb_data = crumb_resp.json()
        crumb_header = {
            crumb_data['crumbRequestField']: crumb_data['crumb']
        }

        #Step 2: Trigger Jenkins job with REPO_URL parameter
        build_resp = requests.post(
            f'{JENKINS_URL}/job/{JOB_NAME}/buildWithParameters',
            auth=(JENKINS_USER, JENKINS_TOKEN),
            headers=crumb_header,
            params={'REPO_URL': repo_url}
        )
        build_resp.raise_for_status()

        # Jenkins returns a queue item location, we need this to track the build
        queue_url = build_resp.headers.get('Location')

        return jsonify({
            'status': 'triggered',
            'message': 'Deployment started!',
            'live_url': APP_LIVE_URL,
            'queue_url': queue_url
     })

    except requests.exceptions.RequestException as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500

@app.route('/build-status')
def build_status():
    queue_url = request.args.get('queue_url')

    if not queue_url:
        return jsonify({'status': 'error', 'message': 'queue_url missing'}), 400


    try:
        # Step 1: check the queue item, find out if build has actually started
        q_resp = requests.get(f'{queue_url}api/json', auth=(JENKINS_USER, JENKINS_TOKEN))
        q_resp.raise_for_status()
        q_data = q_resp.json()

        if 'executable' not in q_data:
            return jsonify({'status': 'queued'})

        build_number = q_data['executable']['number']
        build_url = f'{JENKINS_URL}/job/{JOB_NAME}/{build_number}/'

        #Step 2: get build status (still running? success? failed?)

        b_resp = requests.get(f'{build_url}api/json', auth=(JENKINS_USER, JENKINS_TOKEN))
        b_resp.raise_for_status()
        b_data = b_resp.json()

        #Step 3: get console output text
        c_resp = requests.get(f'{build_url}consoleText', auth=(JENKINS_USER, JENKINS_TOKEN))
        c_resp.raise_for_status()

        return jsonify({
            'status': 'running',
            'building': b_data['building'],
            'result': b_data.get('result'),
            'console': c_resp.text,
            'build_number': build_number
        })

    except requests.exceptions.RequestException as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500



if __name__ == '__main__':
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=True
    )
