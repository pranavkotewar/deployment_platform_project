#!/bin/bash
# health_check.sh wait <app> <host_port>   deploy ke baad one-time check (Jenkins)
# health_check.sh check-all                periodic check + self-healing (systemd timer)
# Healthy = HTTP jawab aaya aur code < 500.

DF="$HOME/deployforge"
REG="$DF/ports.db"
HDB="$DF/health.db"
LOCK="$DF/health.lock"
MAX_RESTARTS=3
FAILS_BEFORE_RESTART=2

is_running() {
    [ -n "$(docker ps -q --filter "name=^${1}$" --filter status=running < /dev/null)" ]
}

exists() {
    [ -n "$(docker ps -aq --filter "name=^${1}$" < /dev/null)" ]
}

probe() {
    local c
    c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$1/" < /dev/null)
    echo "${c:-000}"
}

is_healthy() {
    [ "$1" != "000" ] && [ "$1" -lt 500 ] 2>/dev/null
}

write_one() {
    mkdir -p "$DF"
    exec 6>"$LOCK"
    flock -w 10 6 || return 0
    local tmp
    tmp=$(mktemp "$DF/health.XXXXXX") || return 0
    [ -f "$HDB" ] && awk -v n="$1" 'NF==6 && $1!=n {print}' "$HDB" > "$tmp"
    echo "$1 healthy $2 $(date +%s) 0 0" >> "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$HDB"
}

wait_mode() {
    local APP="$1" PORT="$2" i code
    for ((i=1; i<=15; i++)); do
        if is_running "$APP"; then
            code=$(probe "$PORT")
            if is_healthy "$code"; then
                echo "HEALTH OK: HTTP $code (attempt $i)"
                write_one "$APP" "$code"
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
}

check_all() {
    mkdir -p "$DF"
    exec 8>"$LOCK"
    flock -n 8 || exit 0
    [ -f "$REG" ] || exit 0

    declare -A O_RESTARTS O_FAILS
    if [ -f "$HDB" ]; then
        while read -r n st cd ts rs fl; do
            [ -n "$n" ] || continue
            O_RESTARTS[$n]=${rs:-0}
            O_FAILS[$n]=${fl:-0}
        done < "$HDB"
    fi

    local tmp now name hport cport code status restarts fails
    tmp=$(mktemp "$DF/health.XXXXXX") || exit 1
    now=$(date +%s)

    while read -r name hport cport; do
        [ -n "$name" ] || continue
        restarts=${O_RESTARTS[$name]:-0}
        fails=${O_FAILS[$name]:-0}
        code=$(probe "$hport")

        if is_healthy "$code"; then
            status=healthy; fails=0; restarts=0
        else
            fails=$((fails + 1))
            if [ "$restarts" -ge "$MAX_RESTARTS" ]; then
                status=failed
                if [ $((now % 300)) -lt 15 ]; then
                    if ! exists "$name"; then
                        docker run -d --restart unless-stopped --name "$name" -p "$hport:$cport" "$name:latest" > /dev/null 2>&1 < /dev/null
                    elif ! is_running "$name"; then
                        docker start "$name" > /dev/null 2>&1 < /dev/null
                    fi
                fi
            elif ! exists "$name"; then
                docker run -d --restart unless-stopped --name "$name" -p "$hport:$cport" "$name:latest" > /dev/null 2>&1 < /dev/null
                restarts=$((restarts + 1)); fails=0; status=healing
            elif ! is_running "$name"; then
                docker start "$name" > /dev/null 2>&1 < /dev/null
                restarts=$((restarts + 1)); fails=0; status=healing
            elif [ "$fails" -ge "$FAILS_BEFORE_RESTART" ]; then
                docker restart "$name" > /dev/null 2>&1 < /dev/null
                restarts=$((restarts + 1)); fails=0; status=healing
            else
                status=unhealthy
            fi
        fi
        echo "$name $status $code $now $restarts $fails" >> "$tmp"
    done < "$REG"

    chmod 644 "$tmp"
    mv "$tmp" "$HDB"
}

case "$1" in
    wait)
        [ -n "$2" ] && [ -n "$3" ] || { echo "Usage: health_check.sh wait <app> <host_port>"; exit 1; }
        wait_mode "$2" "$3"
        ;;
    check-all)
        check_all
        ;;
    *)
        echo "Usage: health_check.sh wait <app> <host_port> | check-all"
        exit 1
        ;;
esac
