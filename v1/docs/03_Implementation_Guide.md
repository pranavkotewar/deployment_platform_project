# 03 — Implementation Guide (V1)

Step-by-step setup, in the order it was actually done.

## 1. Provision VMs

- Create two VMs in VirtualBox: `project-vm1`, `project-vm2`.
- Ubuntu 24.04.4 LTS Server, Bridged network adapter, OpenSSH server
  enabled during install.
- On VM1, extend the LVM root partition to use the full disk:

sudo vgs
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
df -h /


## 2. VM1 — base tools

Pre-installed/verified: Java 21 (OpenJDK), Jenkins, Docker, Git,
Python 3.12.

java -version
systemctl status jenkins --no-pager
docker --version
git --version
python3 --version


Complete the Jenkins setup wizard:
1. `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
2. Paste into `http://<VM1-IP>:8080`.
3. Install suggested plugins.
4. Create admin user (username: `jenkins`).

Generate a Jenkins API token:
Jenkins → user menu → **Configure** → **API Token** → **Add new Token**
→ **Generate**. Store it securely (not in Git).

## 3. VM2 — Docker runtime

sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world


## 4. SSH from Jenkins (VM1) to VM2

sudo mkdir -p /var/lib/jenkins/.ssh
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t rsa -b 4096 -N "" -f /var/lib/jenkins/.ssh/id_rsa
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub


On VM2:

mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys # paste the public key
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys


Test from VM1:

sudo -u jenkins ssh -o StrictHostKeyChecking=accept-new projectvm2@<VM2-IP> "docker ps"

Should return an empty container table with no password prompt.

## 5. Sample test application

On VM2, create a minimal static app to use as a deploy target:

`index.html` — any simple page.

`Dockerfile`:
```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

Push to its own GitHub repo (`sample-static-app`), separate from the
project repo.

## 6. Jenkins Pipeline job

Jenkins → **New Item** → name `deploy-pipeline` → type **Pipeline**.

- Tick **This project is parameterized** → add String Parameter
  `REPO_URL`.
- Pipeline → Definition: **Pipeline script**, paste the Jenkinsfile
  (see `v1/Jenkinsfile` in this repo).

Key point: the `docker build` stage uses `--no-cache` so every deploy
picks up the latest commit instead of reusing a stale cached layer.

## 7. Flask backend

cd ~/auto-deploy-system/v1/backend
python3 -m venv venv
source venv/bin/activate
pip install flask requests python-dotenv


`app.py` exposes:
- `GET /` — renders `templates/dashboard.html`
- `POST /deploy` — fetches a Jenkins CSRF crumb, then triggers
  `buildWithParameters` with `REPO_URL`
- `GET /build-status` — resolves the Jenkins queue item to a build
  number, returns live console text and build result

Credentials are read from a `.env` file at the project root
(`JENKINS_USER`, `JENKINS_TOKEN`, `JENKINS_URL`), loaded via
`python-dotenv`. This file is excluded from Git.

## 8. Dashboard

`templates/dashboard.html` — single page with:
- Repo URL input + Deploy button
- Status box (info / success / error states)
- Log viewer that polls `/build-status` every 2.5 seconds and displays
  Jenkins console output live

## 9. Run and test

cd ~/auto-deploy-system/v1/backend
source venv/bin/activate
python app.py

Open `http://<VM1-IP>:5000`, paste the sample app's repo URL, click
Deploy, confirm the live link at `http://<VM2-IP>:9000` works.

## Credential Handling Notes

- Jenkins token and `.env` are never committed to Git
  (`.gitignore` excludes `.env`, `venv/`, `__pycache__/`).
- GitHub pushes use a Personal Access Token (PAT), stored locally via
  `git config --global credential.helper store` to avoid re-entering
  it on every push.
