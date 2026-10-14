#!/bin/bash
echo "== VM1 =="
for u in jenkins deployforge-web deployforge-funnel tailscaled; do printf "%-20s %s\n" "$u" "$(systemctl is-active $u)"; done
curl -s -o /dev/null -w "dashboard local: %{http_code}\n" localhost:5000
echo "== VM2 =="
ssh -o ConnectTimeout=8 projectvm2@my-app 'for u in docker nginx tailscaled deployforge-health.timer deployforge-funnel; do printf "%-26s %s\n" "$u" "$(systemctl is-active $u)"; done; echo "containers: $(docker ps -q | wc -l) running"; curl -s -o /dev/null -w "gateway: %{http_code}\n" localhost:8080'
