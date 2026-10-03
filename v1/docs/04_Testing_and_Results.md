# 04 — Testing and Results (V1)

## Test Environment

- VM1 (`project-vm1`): Jenkins, Flask, Dashboard
- VM2 (`projectvm-2`): Docker runtime
- Test repo: `sample-static-app` (static HTML + nginx:alpine Dockerfile)

## Test Cases

| # | Test Case | Steps | Expected Result | Actual Result |
|---|---|---|---|---|
| 1 | VM1 → VM2 SSH connectivity | Run `ssh -u jenkins ... "docker ps"` from VM1 | No password prompt, empty container table returned | Pass |
| 2 | Jenkins job trigger via API | Flask sends crumb + `buildWithParameters` request | Jenkins queues and starts a build | Pass |
| 3 | End-to-end pipeline run (manual, via Jenkins UI) | Build with Parameters, default `REPO_URL` | Build succeeds, container running on VM2:9000 | Pass |
| 4 | Dashboard deploy flow | Paste repo URL on dashboard, click Deploy | Live logs stream, success message + live link shown | Pass |
| 5 | Live app reachable | Open `http://<VM2-IP>:9000` after deploy | Sample app page loads | Pass |
| 6 | Code update reflected on redeploy | Change `index.html`, push, redeploy | New content visible after refresh | Initially failed — old page still showed |
| 7 | Git push without repeated credential prompt | Run `git push` twice | Second push does not ask for username/PAT | Pass (after fix) |
| 8 | ngrok dashboard tunnel (VM1) | Run `ngrok http --url=<fixed-domain> 5000` | Dashboard reachable via public URL from external network | Pass |
| 9 | ngrok app tunnel (VM2) | Run `ngrok http 9000` | App reachable via public ngrok URL | Pass (after fix — see Issue 4) |
|10 | Dashboard shows correct public app URL | Deploy via dashboard, check returned live link | Live link is VM2's ngrok `https://...` URL, not local IP | Pass (after fix — see Issue 5) |
|11 | One-command start/stop | Run `./start.sh`, then `./stop.sh` | All processes (Flask, both ngrok agents) start and stop cleanly | Pass (after fix — see Issue 6) |

## Issues Found and Fixes

### Issue 1: Stale content after redeploy
**Symptom:** After editing `index.html` and pushing to GitHub, re-running
the pipeline completed successfully, but the live app still showed the
old content.

**Cause:** Docker was reusing a cached image layer for the `COPY`
instruction instead of rebuilding with the new file.

**Fix:** Added `--no-cache` to the `docker build` command in the
Jenkinsfile, forcing a fresh build on every deploy.

### Issue 2: Repeated Git credential prompts
**Symptom:** Every `git push` asked for GitHub username and Personal
Access Token again.

**Fix:** Ran `git config --global credential.helper store` on both VMs
to cache credentials locally after the first successful push.

### Issue 3: Jenkins SSH key save failed (Permission denied)
**Symptom:** `ssh-keygen` for the `jenkins` user failed to save the key
inside `/var/lib/jenkins/.ssh`.

**Cause:** The directory was owned by `root`, not `jenkins`.

**Fix:**

sudo mkdir -p /var/lib/jenkins/.ssh
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh

### Issue 4: VM2 ngrok tunnel failed with ERR_NGROK_334
**Symptom:** Starting ngrok on VM2 while VM1's ngrok was already
running failed with:

ERROR: failed to start tunnel: The endpoint '...' is already online.
ERR_NGROK_334


**Cause:** Free ngrok plan allows only one active tunnel session per
account. Both VMs were configured with the same authtoken.

**Fix:** Created a second ngrok account and configured VM2 with its
own authtoken.

### Issue 5: Dashboard showed local IP instead of public app URL
**Symptom:** After a successful deploy, the live link shown on the
dashboard was always `http://192.168.42.7:9000` (VM2's local IP),
never the ngrok public URL.

**Cause:** `get_vm2_public_url()` queried the wrong ngrok API port
(`4041` instead of `4040`), so the request failed silently and the
function fell back to the hardcoded local IP.

**Fix:** Corrected the port to `4040` (ngrok's default local API
port).

### Issue 6: `stop.sh` did not stop any processes
**Symptom:** Running `./stop.sh` printed "Stopped." but Flask and
ngrok processes were still running (confirmed via `ps aux`).

**Cause:** The script searched for the process pattern
`"python app.py"`, but the actual running process was
`python3 app.py` — `pkill -f` does substring matching, and the
pattern did not match.

**Fix:** Changed the pattern to the broader substring `"app.py"` and
added `-9` to force-kill reliably.

## Summary

All core V1 functionality — dashboard-triggered deployment, live log
streaming, and a reachable deployed app — works end to end. The main
gap found during testing (stale builds) was a Docker caching behavior,
not a design flaw, and was resolved with `--no-cache`.

In addition to the core deployment flow, the system was extended with
public internet access via ngrok tunneling, allowing the dashboard
and deployed app to be reached from any network, not just the local
VM subnet.

## Limitations Carried Into V2

- No automatic health check after deployment — success is reported as
  soon as `docker run` exits, without verifying the app actually
  responds.
- No validation before build (e.g. checking a Dockerfile exists).
- No self-healing if the container crashes after a successful deploy.

These are addressed in V2's pre-validation and health-check stages.
