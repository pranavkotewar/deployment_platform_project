# DeployForge V2: Implementation Guide

## 1. Repository layout

```
auto-deploy-system/
README.md start.sh stop.sh status.sh .gitignore
v1/ (locked)
v2/
Jenkinsfile
scripts/ (8 scripts)
dockerfile-templates/ (static, flask, node)
backend/ (app.py, detect_routes.py, deploy_routes.py, templates/dashboard.html, requirements.txt)
docs/

Secrets (.env, backend/data) are gitignored. Test apps live in separate repos.
```

## 2. Setup order (as built)
1. Tailscale on both VMs with the same account. Hostnames deployforge and my-app. Funnel enabled in the admin console and HTTPS certificates enabled.
2. Scripts: detect, validate, resolve Dockerfile, assign port.
3. Jenkins job deploy-pipeline-v2: Pipeline script from SCM, repo deployment_platform_project, branch main, script path v2/Jenkinsfile. The first run only registers parameters and fails, which is normal.
4. Flask backend and dashboard (venv in v2/backend).
5. VM2: Nginx on port 8080 with a gateway config that includes ~/deployforge/nginx/*.conf. A sudoers rule allows only nginx -t and nginx -s reload for the deploy user.
6. Health timer on VM2 (every 10 seconds after the last run).
7. Tokens, admin password, history.
8. systemd services for auto-start, Funnel on both VMs.

## 3. Configuration (.env in the project root, not in git)
| Variable | Meaning |
|---|---|
| JENKINS_URL, JENKINS_USER, JENKINS_TOKEN | Jenkins API access |
| VM2_HOST | projectvm2@my-app |
| APP_BASE_URL | Public URL of the apps gateway |
| ADMIN_PASSWORD | Admin password, minimum 8 characters, no single quote |

Change the admin password: edit ADMIN_PASSWORD in .env and restart deployforge-web.

## 4. Services
VM1: sudo systemctl status deployforge-web deployforge-funnel jenkins
VM2: sudo systemctl status deployforge-health.timer deployforge-funnel nginx docker
Quick overview: ./status.sh on VM1.

## 5. Development workflow (important)
- Scripts, templates and the Jenkinsfile are read by Jenkins from GitHub on every deploy. Commit and push before testing, otherwise Jenkins overwrites VM2 scripts with the old version.
- Backend or dashboard changes: sudo systemctl restart deployforge-web (debug mode is off).
- Project repo and test repos are different repositories and must not be mixed.

## 6. Useful commands
| Task | Command |
|---|---|
| Registry on VM2 | cat ~/deployforge/ports.db |
| Health data | cat ~/deployforge/health.db |
| Dashboard logs | journalctl -u deployforge-web -n 50 --no-pager |
| Health timer logs | journalctl -u deployforge-health.service -n 20 --no-pager |
| Remove an app (admin) | use the Delete button |

## 7. Problems faced and solutions
| Problem | Solution |
|---|---|
| Funnel URL gave NXDOMAIN, config disappeared | Re-enable Funnel, services recreate it at boot |
| Characters lost when pasting scripts | Verify with grep and bash -n after every paste |
| Flask stopped in background | Run it as a systemd service |
| Health check always said not running | Use docker ps filter instead of docker inspect template |
| Slow tethering made the GitHub check time out | curl header only (-I) with 15 second limit |
| Jenkins failed on invalid APP_NAME but cleanup still ran | PARAMS_OK guard |
| Failed deploy left a crash looping container and a taken name | post failure removes container, route and port |
| Build looked finished while still queued | Treat only SUCCESS, FAILED, ABORTED, UNSTABLE as finished |
| Failed stage showed later steps as failed | First failed step only, the rest skipped |
| Generic Jenkins error hid the real reason | Search the log for specific failure lines first |
| Health timer failed after deploy | Jenkins overwrote VM2 scripts with the old committed version |
| Same name deployed twice during a running build took over the token | Name reservation for 15 minutes |
| Any text was accepted as admin key | Server side verification |
| Static template returned HTTP 403 and looked healthy | Template now fails the build if no index.html exists |
| Dashboard showed old app health during deploy | Panel shows CHECKING until the health check passes |
| Flask debug mode on a public dashboard | debug=False |
| Every deploy re-downloaded dependencies (no-cache builds) | Removed --no-cache, layer cache is used, Flask template installs requirements first |
| Images of deleted apps stayed on VM2 and used space | cleanup.sh purge on Delete and on failed deploy, base images kept |
| Wrong template gave a cryptic Docker error | validate.sh checks package.json (Node) and a .py file (Flask) |
| Framework source repos (expressjs/express, pallets/flask) failed the health check | They are libraries, not applications. Pick a real application repo |
| Deploying the project repo itself failed (no index.html) | Expected. It is platform code, not a deployable app |
| Dashboard URL gave ERR_TIMED_OUT | Funnel listens on port 443 only. Open the URL with https:// |
| Funnel service showed inactive after adding a timer | Timer removed, service back to oneshot with RemainAfterExit |

## 8. Version 2.1 changes (after v2.0)
- Docker builds use the layer cache. The Flask template installs requirements.txt before copying the code.
- Delete and failed deploys remove the images of that app. Base images stay cached.
- validate.sh checks that the selected template fits the folder.
- Boot: deployforge-web does not wait for Jenkins (Flask only calls Jenkins on a deploy request), and the Funnel service starts after deployforge-web. The dashboard answers about 15 seconds after boot. Jenkins needs about 1 minute, so a deploy started in the first minute can show 'Could not reach Jenkins'. Always open the URL with https://.
- Flask apps behind the /apps/name/ route should use ProxyFix(app.wsgi_app, x_prefix=1), because Nginx sends X-Forwarded-Prefix. Without it url_for() builds absolute paths that break.
- Choose real application repos for testing. Libraries and framework sources are not applications.
