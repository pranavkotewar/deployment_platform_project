# DeployForge V2: Testing and Results

## 1. Script tests
| Script | Cases | Result |
|---|---|---|
| detect_apps.sh | single, monorepo, static, Flask repo with templates folder, Node monorepo, compose | Pass |
| validate.sh | pass cases, missing template, wrong folder | Pass |
| resolve_dockerfile.sh | existing, flask, node, static, invalid template | Pass |
| assign_port.sh | assign, same app same port, bad name, bad port, exact release, busy port, unreadable registry keeps data | Pass |
| generate_nginx_route.sh | create, bad name, bad port, remove twice | Pass |
| health_check.sh | stopped container, recreate, repeated failure ends in failed | Pass |
| record.sh | add, update, reject foreign repo, remove | Pass |

## 2. Pipeline tests
| Test | Expected | Result |
|---|---|---|
| Defaults deploy | All stages green | Pass |
| Monorepo folder with Dockerfile | Success, new port | Pass |
| No Dockerfile and no template | Fails at Validate with reason | Pass |
| Invalid app name | Stops at Check Parameters, no remote command | Pass |
| Flask template on a repo without Flask app | Fails at Health Check, container, route and port removed | Pass |

## 3. Backend API tests
check-name, deploy rejection of invalid input, deploy status for success and both failure types, token handling, admin check, manage actions with no token, wrong token, correct token and admin, 404 for apps outside the registry. All passed.

## 4. Security tests
| Test | Result |
|---|---|
| Tokens file stores only hashes | Pass |
| Same name without token is rejected | Pass |
| Same name during a running deploy is rejected | Pass |
| Wrong admin password does not enable admin mode | Pass |
| Incognito window sees no manage buttons | Pass |
| Delete is not undone by self-healing | Pass |

## 5. End-to-end tests (demo apps)
| # | Test | Result |
|---|---|---|
| 1 | Static app with own Dockerfile | Pass |
| 2 | Monorepo scan, compose app greyed out | Pass |
| 3 | Frontend folder with Dockerfile | Pass |
| 4 | Flask template, API data loads with relative path | Pass |
| 5 | Node template | Pass |
| 6 | Static template with CSS | Pass |
| 7 | Two deployments at once (run one after another) | Pass |
| 8 | Wrong template (failure case) | Pass, no leftovers |
| 9 | Redeploy by owner | Pass |
| 10 | Other browser cannot reuse the name | Pass |
| 11 | Public links through Funnel | Pass |
| 12 | Container removed, self-healing recreates it | Pass |
| 13 | Logs, Restart, Delete actions | Pass |

## 6. Persistence and network tests
| Test | Result |
|---|---|
| VM2 restart: services, containers, health timer, Funnel return | Pass |
| VM1 restart: dashboard and Funnel return, history intact, admin remembered | Pass |
| Switch from USB tethering to Wi-Fi, full deploy afterwards | Pass |

## 6A. Tests after v2.0 (V2.1)
| Test | Result |
|---|---|
| Redeploy of the same app reuses cached layers and builds faster | Pass |
| Delete removes all images of the app | Pass |
| Static template on a repo without index.html fails with a clear message | Pass |
| Framework source repos (express, flask) fail the health check and leave nothing behind | Pass |
| Node template on a folder without package.json fails at Validate | Pass |
| Flask app with ProxyFix deployed under /apps/name/ (forms and redirects work) | Pending |

## 7. Known limitations
- Applications must use relative paths. Apps using absolute paths such as /style.css can break under /apps/name/.
- Templates cover common layouts only. Django, FastAPI, apps that need a build step and apps with a hardcoded port need their own Dockerfile.
- Detection looks at the repo root and one folder level.
- docker-compose and multi-container apps are not supported.
- Builds run one at a time (disableConcurrentBuilds), applications run in parallel.
- If a redeploy fails, the previous version of that app is also gone (no safe swap or rollback).
- A name stays reserved for 15 minutes after a failed deploy, and the reservation resets when the dashboard restarts.
- Credentials are stored in plain text files on the VM (.env), acceptable for a learning project.
- Free Tailscale plan and the public DNS delay can affect the first access.
- With the layer cache on, a Dockerfile step like git clone or apt-get update can reuse an old result. Delete the app and deploy again for a fully fresh build.
- Library or framework source repositories are not applications and fail the health check.
- Flask apps must use ProxyFix, and every app must use relative paths, to work under /apps/name/.
- The dashboard URL must be opened with https://. After a VM start allow 30 to 40 seconds.

## 8. Next version (V3)
Kubernetes (k3s) with probes, rollback with image versions, parallel builds with per-build files, multi-container support, real accounts and roles.
