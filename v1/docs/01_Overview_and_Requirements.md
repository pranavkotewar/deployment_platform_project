# 01 — Overview and Requirements (V1)

## Problem Statement

Manually deploying an application involves repetitive steps — cloning code,
writing a Dockerfile, building an image, running a container, and checking
whether it actually works. Doing this by hand for every small change is
slow and error-prone, especially for a student learning DevOps workflows.

## Objective

Build a system where a user can paste a GitHub repository URL into a web
dashboard and have it automatically built and deployed as a running
container, with a CI/CD tool (Jenkins) orchestrating the process.

## Scope of V1

**In scope:**
- Web dashboard to accept a repo URL and trigger deployment
- Flask backend to bridge dashboard and Jenkins
- Jenkins pipeline: clone → build → run
- Live build log streaming to the dashboard
- Live link to the deployed app

**Out of scope (deferred to later versions):**
- Application template selection (V2)
- Automatic Dockerfile generation (V2)
- Pre-deployment validation (V2)
- Health checks and self-healing (V2)
- Kubernetes orchestration (V3)
- Rollback and deployment history (V3)

## Target User

A developer who has a GitHub repository containing a working `Dockerfile`
and wants to deploy it quickly without manually running Docker commands.

## Tools and Technologies

| Category | Tool |
|---|---|
| Virtualization | VirtualBox |
| OS | Ubuntu 24.04.4 LTS Server |
| CI/CD | Jenkins |
| Containers | Docker |
| Backend | Python 3.12, Flask |
| Frontend | HTML, CSS, vanilla JavaScript |
| Version control | Git, GitHub |

## Functional Requirements

1. User can enter a GitHub repo URL in the dashboard.
2. System triggers a Jenkins build with that URL as a parameter.
3. System clones the repo, builds a Docker image, and runs a container.
4. User can see live logs of the deployment in progress.
5. User can see a live link to the deployed application on success.
6. User sees an error message if deployment fails.

## Non-Functional Requirements

- Should run on modest hardware (8 GB RAM, dual-VM setup).
- Should not require internet access beyond GitHub/package repositories.
- Setup should be reproducible from documented commands.
