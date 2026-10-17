# DeployForge V2: Architecture and Design

## 1. Overview

```
Dashboard path:
  Internet -> https://deployforge.<tailnet>.ts.net
    -> Tailscale Funnel (VM1) -> Flask dashboard :5000
    -> Jenkins :8080 (job deploy-pipeline-v2)
    -> SSH over Tailscale (projectvm2@my-app)

Application path:
  Internet -> https://my-app.<tailnet>.ts.net/apps/<name>/
    -> Tailscale Funnel (VM2) -> Nginx gateway :8080
    -> /apps/app1/ -> 127.0.0.1:9001
    -> /apps/app2/ -> 127.0.0.1:9002
    -> /apps/app3/ -> 127.0.0.1:9003

VM2 runs: Docker containers (restart policy unless-stopped),
registries (ports.db, health.db, deployments.db), health timer.
```


## 2. Machines
| VM | Hostname | Role |
|---|---|---|
| VM1 | deployforge | Dashboard (Flask), Jenkins, Funnel for the dashboard |
| VM2 | my-app | Docker runtime, Nginx, registries, health timer, Funnel for apps |

Both VMs use a Bridged adapter. They talk to each other only through Tailscale names, so a change of Wi-Fi or LAN IP does not break the system.

## 3. Deployment pipeline (Jenkinsfile)
| Stage | Dashboard step | Purpose |
|---|---|---|
| Check Parameters | Repository Cloned | Regex checks on all inputs |
| Copy Scripts to VM2 | Repository Cloned | scp scripts and templates from the repo |
| Clone Repository | Repository Cloned | git clone on VM2 |
| Validate | Validation Passed | validate.sh |
| Resolve Dockerfile | Docker Image Built | Dockerfile priority rule, container port |
| Build Image | Docker Image Built | docker build, tags build number and latest |
| Assign Port | Container Started | assign_port.sh |
| Run Container | Container Started | docker run with restart policy unless-stopped |
| Create Route | Container Started | Nginx route, waits until active |
| Health Check | Health Check | health_check.sh wait |

post always: cleanup.sh (work folder, old image tags, dangling images). post success: record the deployment. post failure: remove container, route and port.

## 4. Scripts (all in v2/scripts)
| Script | Runs on | Job |
|---|---|---|
| detect_apps.sh | VM2 | Scan repo, output JSON of apps |
| validate.sh | VM2 | 5 pre-deployment checks |
| resolve_dockerfile.sh | VM2 | Use existing Dockerfile or copy template, print container port |
| assign_port.sh | VM2 | Port registry (assign, get, list, release, check) with locking |
| generate_nginx_route.sh | VM2 | Create or remove /apps/name/ route |
| health_check.sh | VM2 | wait mode (deploy) and check-all mode (timer, self-healing) |
| record.sh | VM2 | Deployment history records |
| cleanup.sh | VM2 | Safe cleanup |

## 5. Key design rules
- Dockerfile priority: an existing Dockerfile is always used as is. Templates are only for repos without one.
- Detection: root Dockerfile or compose means single app mode, otherwise root plus one level of folders.
- Templates: static (nginx, container port 80), flask (gunicorn, 5000, entrypoint finds app, application or create_app), node (npm start or main file, 3000).
- Health: HTTP answer below 500 is healthy (4xx counts as the app is responding). No answer or 5xx is unhealthy.
- Self-healing: container stopped, start it. Container missing, recreate from its image. Two failed checks, restart. After 3 restarts the status is failed, with one recovery attempt every 5 minutes.

- Image cache (V2.1): builds use the Docker layer cache, so a redeploy reuses unchanged layers. The Flask template copies and installs requirements.txt before the app code, so a code change does not reinstall dependencies. Base images (node, python, nginx) are shared and stay cached.
- Template check (V2.1): validate.sh also checks that the chosen template fits the folder (Node needs package.json, Flask needs a .py file) and fails early with a clear reason.
- Image cleanup (V2.1): Delete and a failed deploy remove all images of that app (cleanup.sh purge). Base images are never removed.

## 6. Data on VM2 (~/deployforge)
| File | Content |
|---|---|
| ports.db | name host_port container_port |
| health.db | name status http_code time restarts fails |
| deployments.db | name repo app_path template time |
| nginx/name.conf | one route per app |

## 7. Access model (no login)
- Deploying a new name creates a random token (32 hex characters). The browser stores it in localStorage. The server stores only its SHA-256 hash (v2/backend/data/tokens.json, not in git).
- Logs, Restart and Delete need the owner token or the admin password. Everyone can see the list, status and links.
- A name already in use can only be redeployed by its owner. A name being deployed is reserved for 15 minutes.
- Admin password is in .env (ADMIN_PASSWORD) and is verified by the server.
- Manage actions only work on apps present in the registry.

## 8. Dashboard
Single page, dark theme: New Deployment (scan, application, template, name, option cards), Deployment Status (5 steps), Application Health, Live Application, Deployments table (scrollable, with actions) and Deployment Logs. Backend routes: /detect, /check-name, /deploy, /deploy-status, /health, /history, /manage, /admin-check.

## 9. Startup (systemd)
VM1: jenkins, deployforge-web, deployforge-funnel. VM2: docker, nginx, tailscaled, deployforge-health.timer, deployforge-funnel. Containers return after boot through the restart policy.

## 10. Reuse for V3
Application name, port and route mapping, health status and deployment history are kept in simple files, so V3 can move them to Kubernetes objects.
