#!/bin/bash
# health_check.sh wait <app> <host_port>
# Deploy ke baad: container running hai aur HTTP jawab de raha hai?
# 000 (connection fail) aur 5xx = unhealthy. 2xx/3xx/4xx = app respond kar rahi hai.
# (Step 10 mein isi file mein periodic mode aur self-healing judega)

MODE="$1"
APP="$2"
PORT="$3"
TRIES=15

is_running() {
    [ -n "$(docker ps -q --filter "name=^${APP}$" --filter status=running < /dev/null)" ]
}

case "$MODE" in
    wait)
        for ((i=1; i<=TRIES; i++)); do
            if is_running; then
                code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$PORT/")
                if [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
                    echo "HEALTH OK: HTTP $code (attempt $i)"
                    exit 0
                fi
                echo "Attempt $i: no healthy response yet (HTTP $code)"
            else
                echo "Attempt $i: container is not running"
            fi
            sleep 2
        done
        echo "--- last container logs ---"
        docker logs --tail 20 "$APP" 2>&1
        echo "HEALTH CHECK FAILED: application did not respond on port $PORT"
        exit 1
        ;;
    *)
        echo "Usage: health_check.sh wait <app> <host_port>"
        exit 1
        ;;
esac
