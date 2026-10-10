#!/bin/bash
#health_check.sh wait <app> <host_port>
# After deploy: is container running & HTTP responds ?
# 000 (connection fail) and 5xx = unhealthy, 2xx/3xx/4xx = app respods.
# (In step 10 'periodic mode and self-healing will be added to this same file.')

MODE="$1"
APP="$2"
PORT="$3"
TRIES=15

case "$MODE" in 
    wait)
        for ((i=1; i<=TRIES; i++)); do
            running=$(docker inspect -f '{{.state.Running}}' "$APP" 2>/dev/null)
            if [ "$running" = "true" ]; then
                code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$PORT/")
                if  [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
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
