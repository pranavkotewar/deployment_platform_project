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


## Summary

All core V1 functionality — dashboard-triggered deployment, live log
streaming, and a reachable deployed app — works end to end. The main
gap found during testing (stale builds) was a Docker caching behavior,
not a design flaw, and was resolved with `--no-cache`.

## Limitations Carried Into V2

- No automatic health check after deployment — success is reported as
  soon as `docker run` exits, without verifying the app actually
  responds.
- No validation before build (e.g. checking a Dockerfile exists).
- No self-healing if the container crashes after a successful deploy.

These are addressed in V2's pre-validation and health-check stages.
