# Automated Deployment System with Self-Healing and Intelligent Rollback

A college final-year project that automates the process of deploying a GitHub
repository through a web dashboard, using Jenkins, Docker, and (in later
versions) Kubernetes.

Built progressively across three versions:
- **V1** — Core flow: dashboard → Jenkins → Docker deploy
- **V2** — Templates, validation, health checks, self-healing
- **V3** — Kubernetes (k3s), rollback, deployment history

This README covers **Version 1**.

---

## What V1 Does

1. User opens the dashboard and pastes a GitHub repo URL (the repo must
   contain a `Dockerfile`).
2. User clicks **Deploy**.
3. Flask backend triggers a Jenkins pipeline with that repo URL.
4. Jenkins SSHes into a second VM, clones the repo, builds a Docker image,
   and runs it as a container.
5. The dashboard polls Jenkins and shows live build logs.
6. On success, a live link to the deployed app is shown.

---

## Architecture (V1)

Two Ubuntu VMs, Bridged networking:

| VM | Role | Runs |
|---|---|---|
| VM1 (Control) | `project-vm1` | Jenkins, Flask backend, Dashboard |
| VM2 (Runtime) | `projectvm-2` | Docker (app containers) |

Browser → Flask (VM1:5000) → Jenkins (VM1:8080) → SSH → VM2
├─ git clone
├─ docker build
└─ docker run (:9000)


Full diagram and component breakdown: see [`v1/docs/02_Architecture_and_Design.md`](v1/docs/02_Architecture_and_Design.md).

---

## Tech Stack

- **VMs:** VirtualBox, Ubuntu 24.04.4 LTS Server (Bridged adapter)
- **CI/CD:** Jenkins (Pipeline job, SSH-based remote execution)
- **Containers:** Docker (`docker.io`)
- **Backend:** Python 3.12, Flask, `requests`, `python-dotenv`
- **Frontend:** Plain HTML/CSS/JavaScript (no framework)
- **Version control:** Git, GitHub (PAT-based auth)

---

## Repository Structure

auto-deploy-system/
├── README.md
├── .gitignore
├── start.sh
├── stop.sh
└── v1/
├── Jenkinsfile
├── docs/
│ ├── 01_Overview_and_Requirements.md
│ ├── 02_Architecture_and_Design.md
│ ├── 03_Implementation_Guide.md
│ └── 04_Testing_and_Results.md
└── backend/
├── app.py
└── templates/
└── dashboard.html


Sample test app (separate repo, used as deploy target):
`https://github.com/pranavkotewar/sample-static-app`

---

## How It Was Built — End-to-End Setup

> Full step-by-step with explanations is in
> [`v1/docs/03_Implementation_Guide.md`](v1/docs/03_Implementation_Guide.md).
> This section is a quick command reference.

### 1. VM setup
- 2 VMs in VirtualBox: `project-vm1` (2 GB RAM, 30 GB disk) and
  `project-vm2` (2 GB RAM, 30 GB disk), both Ubuntu 24.04.4 LTS Server,
  Bridged networking.
- Extended root partition on VM1 (LVM):
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv


### 2. VM1 — Jenkins, Docker, Python

java -version # OpenJDK 21 (pre-installed)
sudo systemctl status jenkins
docker --version
python3 --version
sudo apt install -y python3-venv python3-pip

- Completed Jenkins setup wizard (unlock → install suggested plugins →
  create admin user `jenkins`).
- Generated a Jenkins API token (Jenkins → user → Configure → API Token).

### 3. VM2 — Docker runtime

sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world


### 4. SSH: Jenkins (VM1) → VM2

sudo mkdir -p /var/lib/jenkins/.ssh
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh
sudo -u jenkins ssh-keygen -t rsa -b 4096 -N "" -f /var/lib/jenkins/.ssh/id_rsa
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub

Public key copied into `~/.ssh/authorized_keys` on VM2. Tested with:

sudo -u jenkins ssh projectvm2@<VM2-IP> "docker ps"


### 5. Sample app + two GitHub repos
- `sample-static-app` — test repo with `index.html` + 3-line `Dockerfile`
  (`FROM nginx:alpine`, `COPY`, `EXPOSE 80`).
- `deployment_platform_project` — this project repo.
- GitHub push uses a Personal Access Token (PAT), saved locally with:

git config --global credential.helper store


### 6. Jenkins Pipeline job
- Created Pipeline job `deploy-pipeline`, parameterized with `REPO_URL`.
- Jenkinsfile (`v1/Jenkinsfile`) SSHes into VM2 and runs:

git clone <REPO_URL> ~/deploy-app
docker build --no-cache -t sample-app ~/deploy-app
docker run -d -p 9000:80 --name sample-app sample-app

  `--no-cache` is used so every deploy picks up the latest code.

### 7. Flask backend

cd ~/auto-deploy-system/v1/backend
python3 -m venv venv
source venv/bin/activate
pip install flask requests python-dotenv
python app.py

- `/` serves the dashboard.
- `/deploy` triggers the Jenkins job via its REST API (crumb + token auth).
- `/build-status` polls Jenkins for live console output and build result.

### 8. Dashboard
- Single HTML page (`templates/dashboard.html`) with a repo URL input,
  Deploy button, live log viewer, and success/error status box.
- Polls `/build-status` every 2.5 seconds until the build finishes.

---

## Running It
VM1

cd ~/auto-deploy-system/v1/backend
source venv/bin/activate
python app.py

Open `http://<VM1-IP>:5000`, paste a repo URL (must contain a Dockerfile),
click **Deploy**. Live app appears at `http://<VM2-IP>:9000`.

---

## Public Access (ngrok Tunneling)

Both the dashboard (VM1) and the deployed app (VM2) can be made
accessible from any network (not just the local VM network) using
ngrok tunnels.

- **Dashboard (VM1):** uses a free static ngrok domain, so the URL
  never changes between restarts.
- **App (VM2):** uses a free dynamic ngrok domain, which changes each
  time it restarts. The dashboard automatically fetches VM2's current
  public URL from ngrok's local API (`localhost:4040/api/tunnels`) and
  displays it after each deploy, so the changing URL is never a
  problem in practice.

Because ngrok's free plan allows only one active tunnel per account,
VM1 and VM2 use **two separate ngrok accounts** (two authtokens).

### Starting everything

cd ~/auto-deploy-system
./start.sh

This starts Flask, VM1's ngrok tunnel (dashboard), and VM2's ngrok
tunnel (app, started remotely over SSH) in one command.

### Stopping everything

./stop.sh


### One-time setup (per VM)

curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok
ngrok config add-authtoken <token>

VM1 also claims a free static domain from the ngrok dashboard
(Cloud Edge → Domains), used in `start.sh`.

## Known Limitations (V1)

- **Single Dockerfile at repo root only.** The pipeline runs
  `docker build` against the root of the cloned repo. If a repo
  contains multiple applications (e.g. `app1/Dockerfile`,
  `app2/Dockerfile` in separate folders), the build will fail to find
  a Dockerfile, and there is no way to specify which sub-folder or
  app to deploy. The dashboard only accepts a repo URL, not a path.
- **Fixed internal container port (80) assumed.** `docker run` always
  maps host port 9000 to container port 80
  (`-p 9000:80`). Any repo deployed must have its app listening on
  port 80 inside the container (as declared via `EXPOSE 80` in its
  Dockerfile), or the port mapping will be wrong and the app will not
  be reachable, even if the build succeeds.
- *Manual trigger only * — no GitHub webhook / auto-deploy on push.
- *No template selection* — assumes the repo already has a working
  Dockerfile (and that the user wrote it correctly).
- *No pre-deployment validation* (e.g. checking that a Dockerfile
  exists before triggering a build).
- *No health checks* after deployment — success is reported as soon as
  `docker run` exits, without verifying the app actually responds.
- *No self-healing* if the container crashes after a successful deploy.
- *No Kubernetes*: / rollback (planned for V3).
- *Credentials*: (Jenkins token, PAT, ngrok authtoken) are stored in
  plain text (`.env`, `.git-credentials`, ngrok config) — acceptable
  for a local learning VM, not for production.
- *ngrok free-plan constraints*: one active tunnel per account (two
  accounts used, one per VM), 20k requests/month, 1GB bandwidth/month,
  and a browser warning interstitial on first visit to each tunnel.
---

## Roadmap

- **V2:** template selection, Dockerfile auto-generation, pre-validation,
  health checks, `--restart on-failure` self-healing.
- **V3:** replace Docker-only runtime with k3s, `kubectl rollout undo`
  for rollback, versioned image tags, deployment history on dashboard.

