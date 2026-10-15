# DeployForge V2: Overview and Requirements

## 1. Problem statement
Deploying a web application normally needs manual steps: cloning code, writing a Dockerfile, building, choosing a port, exposing it and watching whether it keeps running. DeployForge automates this. A user pastes a GitHub repository URL, and the system builds, runs, exposes and monitors the application.

## 2. Objective of Version 2
V1 proved the core flow (dashboard, Flask, Jenkins, Docker, public link). V2 adds a reliability layer:

1. Pre-deployment validation with clear failure reasons
2. Application templates (Static, Flask, Node.js) when the repo has no Dockerfile
3. Detection of multiple applications in one repository
4. Several applications running at the same time
5. Automatic port assignment
6. Persistence: deployments survive a VM restart
7. Health check (deploy time and periodic)
8. Self-healing with limited retries
9. Per-deployment token and admin password (no login system)
10. Stable public URLs through Tailscale Funnel

Rollback is not part of V2 (planned for V3).

## 3. Scope
In scope: single-container applications, one Dockerfile or one template per app, path based routing (/apps/name/), up to 99 applications (ports 9001 to 9099).
Out of scope: docker-compose or multi-container apps, rollback, parallel builds, user accounts, Kubernetes.

## 4. Tools and technologies
| Area | Tool |
|---|---|
| Virtualization | VirtualBox, 2 VMs, Ubuntu 24.04 Server, Bridged network |
| CI/CD | Jenkins (declarative pipeline, Pipeline Stage View plugin) |
| Runtime | Docker |
| Reverse proxy | Nginx on VM2, port 8080 |
| Public access | Tailscale Funnel (stable HTTPS URLs) |
| Backend | Python Flask |
| Automation | Bash scripts, systemd services and timer |
| Frontend | HTML, CSS, JavaScript (single page dashboard) |
| Source control | Git and GitHub (project repo and test repos kept separate) |

## 5. Functional requirements
- FR1: Scan a repository and list applications (root and one level deep).
- FR2: Mark docker-compose apps as unsupported with a clear reason.
- FR3: Use the repo Dockerfile if present, otherwise generate one from a template.
- FR4: Validate Docker, folder, Dockerfile or template, disk space and GitHub access before building.
- FR5: Assign a free port automatically and keep it stable for the same app.
- FR6: Create an Nginx route /apps/name/ for every app.
- FR7: Verify the application responds before reporting success.
- FR8: Check health every 10 seconds and restart unhealthy apps (maximum 3 restarts, then failed).
- FR9: Show stage-wise status, logs, failure reason, health and live link on the dashboard.
- FR10: Allow Logs, Restart and Delete only to the owner (token) or the admin (password).

## 6. Non-functional requirements
- Prototype level and easy to explain, no unnecessary complexity.
- Restart safe: services start at boot.
- Network independent: VM to VM traffic uses Tailscale names, not LAN IPs.
- Secrets stay out of git (.env, tokens).

## 7. Version plan
| Version | Focus |
|---|---|
| V1 | Core flow |
| V2 | Reliability (this document) |
| V3 | Kubernetes (k3s), rollback, parallel builds, multi-container apps |
