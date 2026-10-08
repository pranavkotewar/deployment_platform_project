#!/bin/bash
# resolve_dockerfile.sh <repo_dir> <app_path> <template> <templates_dir>
# Dockerfile-priority rule: existing Dockerfile > template.
# last line: CONTAINER_PORT=<port>

REPO_DIR="$1"
APP_PATH="${2:-.}"
TEMPLATE="$3"
TEMPLATES_DIR="$4"

APP_DIR="$REPO_DIR/$APP_PATH"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: application folder not found ($APP_PATH)"
    exit 1
fi

if [ -f "$APP_DIR/Dockerfile" ]; then
    echo "Using existing Dockerfile"
else
    if [ ! -f "$TEMPLATES_DIR/$TEMPLATE/Dockerfile" ]; then
        echo "ERROR: template not found ($TEMPLATE)"
        exit 1
    fi
    cp "$TEMPLATES_DIR/$TEMPLATE/Dockerfile" "$APP_DIR/Dockerfile"
    echo "Generated Dockerfile from template: $TEMPLATE"
fi

PORT=$(grep -i '^EXPOSE' "$APP_DIR/Dockerfile" | head -1 | awk '{print $2}' | cut -d/ -f1)
case "$PORT" in
    ''|*[!0-9]*) PORT=80 ;;
esac

echo "CONTAINER_PORT=$PORT"
