# 02 — Architecture and Design (V1)

## VM Layout

| VM | Hostname | Role | Specs |
|---|---|---|---|
| VM1 | `project-vm1` | Control plane: Jenkins, Flask, Dashboard | 2 GB RAM, 30 GB disk |
| VM2 | `projectvm-2` | Runtime: Docker containers | 2 GB RAM, 30 GB disk |

Both VMs use VirtualBox **Bridged networking**, so each gets its own IP on
the host's network (no NAT port-forwarding needed).

## Architecture Diagram

Browser (Host)
|
v
+--------------------- VM1 (project-vm1) ---------------------+
| |
| Dashboard (HTML) --POST /deploy--> Flask (port 5000) |
| | |
| | REST API call |
| | (crumb + token) |
| v |
| Jenkins (port 8080) |
| Job: deploy-pipeline |
| Param: REPO_URL |
+-------------------------------|-------------------------------+
| SSH (jenkins user, RSA key)
v
+--------------------- VM2 (projectvm-2) -----------------------+
| |
| [1] git clone <REPO_URL> ~/deploy-app |
| [2] docker build --no-cache -t sample-app ~/deploy-app |
| [3] docker run -d -p 9000:80 --name sample-app sample-app |
| |
| Container running on :9000 |
+----------------------------------------------------------------+
|
v
http://<VM2-IP>:9000 (live link)


## Data Flow

1. User submits a repo URL via the dashboard form.
2. Browser sends a `POST /deploy` request to Flask (AJAX, no page reload).
3. Flask fetches a CSRF crumb from Jenkins, then calls
   `POST /job/deploy-pipeline/buildWithParameters` with `REPO_URL`.
4. Jenkins queues and starts the build; Flask returns the queue URL to
   the browser.
5. Browser polls `GET /build-status?queue_url=...` every 2.5 seconds.
6. Flask resolves the queue item to a build number, fetches
   `consoleText` from Jenkins, and returns it along with build state.
7. Once the build finishes, Flask returns `result: SUCCESS` or a failure
   result; the dashboard shows the live link or an error.

## Why SSH Instead of Installing Docker on VM1

Jenkins runs on VM1 but does not build or run containers locally. It
connects to VM2 over SSH (passwordless, RSA key for the `jenkins` system
user) and runs Docker commands there. This separates the "control" role
(scheduling, orchestration) from the "runtime" role (actually running
the app), which mirrors how real deployment systems separate CI servers
from the infrastructure they deploy to.

## Components

| Component | Responsibility | Runs on |
|---|---|---|
| Dashboard (HTML/JS) | Collect repo URL, show status/logs | Browser |
| Flask backend | Bridge dashboard ↔ Jenkins, expose `/deploy` and `/build-status` | VM1 |
| Jenkins | Orchestrate the pipeline | VM1 |
| Jenkinsfile | Defines clone/build/run stages | VM1 (job config) |
| Docker | Build image, run container | VM2 |

## Key Design Decisions

- **Polling over WebSockets** for log streaming — simpler to implement
  and sufficient for a single-user local dashboard.
- **`docker build --no-cache`** — guarantees every deploy reflects the
  latest commit, avoiding stale cached layers.
- **`JENKINS_URL=http://localhost:8080`** instead of a VM IP — Flask and
  Jenkins run on the same VM, so this stays correct even if the VM's
  network IP changes.
- **Credentials in `.env`**, excluded from Git via `.gitignore` — keeps
  secrets out of version control.
