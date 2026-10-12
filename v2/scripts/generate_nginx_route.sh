#!/bin/bash
# generate_nginx_route.sh create <name> <host_port> | remove <name>
# Route: /apps/<name>/  ->  127.0.0.1:<host_port>

NGX_DIR="$HOME/deployforge/nginx"
GATEWAY="http://localhost:8080"
CMD="$1"
NAME="$2"
PORT="$3"

die() { echo "ERROR: $1"; exit 1; }

valid_name() {
    echo "$1" | grep -qE '^[a-z0-9][a-z0-9-]{0,40}$'
}

reload_nginx() {
    sudo -n /usr/sbin/nginx -t < /dev/null > /dev/null 2>&1 || return 1
    sudo -n /usr/sbin/nginx -s reload < /dev/null > /dev/null 2>&1
}

mkdir -p "$NGX_DIR" || die "cannot create $NGX_DIR"
valid_name "$NAME" || die "invalid app name"
CONF="$NGX_DIR/$NAME.conf"

case "$CMD" in
    create)
        echo "$PORT" | grep -qE '^[0-9]{1,5}$' || die "invalid port"
        [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "invalid port"

        [ -f "$CONF" ] && cp "$CONF" "$CONF.bak"
        printf 'location = /apps/%s { return 301 /apps/%s/; }\nlocation /apps/%s/ {\n    proxy_pass http://127.0.0.1:%s/;\n    proxy_set_header Host $host;\n    proxy_set_header X-Real-IP $remote_addr;\n    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n    proxy_set_header X-Forwarded-Prefix /apps/%s;\n}\n' "$NAME" "$NAME" "$NAME" "$PORT" "$NAME" > "$CONF" || die "cannot write route file"

        if ! reload_nginx; then
            if [ -f "$CONF.bak" ]; then mv "$CONF.bak" "$CONF"; else rm -f "$CONF"; fi
            reload_nginx
            die "nginx config test failed, route not created"
        fi
        rm -f "$CONF.bak"

        for i in 1 2 3 4 5 6 7 8 9 10; do
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$GATEWAY/apps/$NAME" < /dev/null)
            if [ "$code" = "301" ]; then
                echo "ROUTE_OK /apps/$NAME/"
                exit 0
            fi
            sleep 1
        done
        die "route did not become active"
        ;;
    remove)
        rm -f "$CONF" "$CONF.bak"
        reload_nginx || echo "WARNING: nginx reload failed"
        echo "Route removed ($NAME)"
        ;;
    *)
        echo "Usage: generate_nginx_route.sh create <name> <host_port> | remove <name>"
        exit 1
        ;;
esac
