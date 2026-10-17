#!/bin/bash
# cleanup.sh <app> <workdir>
# Remove Temp folder, keep each app's latest 2 image tags, danging images prune.
# docker rmi without -f: running container's image does not deletes.

if [ "$1" = "purge" ]; then
    P="$2"
    echo "$P" | grep -qE '^[a-z0-9][a-z0-9-]{0,40}$' || exit 1
    docker images --format '{{.Repository}}:{{.Tag}}' < /dev/null | grep "^${P}:" | while read -r i; do
        docker rmi "$i" > /dev/null 2>&1 < /dev/null || true
    done
    docker image prune -f > /dev/null 2>&1 < /dev/null
    exit 0
fi

APP="$1"
WORK="$2"

case "$WORK" in
    deployforge/work/?*) rm -rf "$HOME/$WORK" ;;
esac

if [ -n "$APP" ]; then
    docker images --format '{{.Tag}}' "$APP" < /dev/null | grep -E '^[0-9]+$' | sort -rn | tail -n +3 | while read -r t; do
        docker rmi "$APP:$t" > /dev/null 2>&1 < /dev/null || true
    done
fi

docker image prune -f > /dev/null 2>&1 < /dev/null
exit 0
