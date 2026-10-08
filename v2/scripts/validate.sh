#! /bin/bash
# validate.sh <repo_dir> <app_path> <dockerfile_present> <template>
# Prevalidation before Deploy. if any check fails then return exit 1.

REPO_DIR="$1"
APP_PATH="${2:-.}"
DOCKERFILE_PRESENT="$3"
TEMPLATE="$4"
MIN_DISK_MB=1024

FAILED=0
REASON=""

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILED=1; [ -z "$REASON" ] && REASON="$1"; }

echo "Running pre-deployment validation..."

#1. Docker daemon
if docker info >/dev/null 2>&1; then
    pass "Docker daemon is running"
else
    fail "Docker is not running or not accessible"
fi

#2. App folder
APP_DIR="$REPO_DIR/$APP_PATH"
if [ -d "$APP_DIR" ]; then
    pass "Application folder found ($APP_PATH)"
else
    fail "Application folder not found in repository ($APP_PATH)"
fi

#3. Dockerfile or template
if [ -f "$APP_DIR/Dockerfile" ]; then
    pass "Dockerfile found, it will be used as is"
elif [ "$DOCKERFILE_PRESENT" = "true" ]; then
    fail "Dockerfile was expected but not found"
else
    case "$TEMPLATE" in
        static|flask|node) pass "No Dockerfile, template selected: $TEMPLATE" ;;
        *) fail "No Dockerfile and no valid template selected" ;;
    esac
fi

#4. Disk space (MB)
FREE_MB=$(df -Pm "$HOME" | awk 'NR==2 {print $4}')
if  [ "${FREE_MB:-0}" -ge "$MIN_DISK_MB" ]; then
    pass "Disk space OK (${FREE_MB} MB free)"
else
    fail "Not enough disk space (${FREE_MB} MB free, ${MIN_DISK_MB} MB needed)"
fi

#5. GitHub reachable
if curl -fsS -o /dev/null --max-time 8 https://github.com; then
    pass "GitHub is reachable"
else
    fail "GitHub is not reachable (check internet connection)"
fi

echo "------"
if [ "$FAILED" -eq 0 ]; then
    echo "VALIDATION PASSED"
    exit 0
else
    echo "VALIDATION FAILED: $REASON"
    exit 1
fi
