#!/bin/sh
# Flask app ka entrypoint dhoondhta hai aur gunicorn se chalata hai.
cd /app
for p in app.py main.py server.py wsgi.py run.py application.py app/__init__.py; do
  [ -f "$p" ] || continue
  mod=$(echo "$p" | sed 's#/__init__\.py$##; s#\.py$##; s#/#.#g')
  for obj in app application; do
    if grep -qE "^$obj ?=" "$p"; then
      echo "DeployForge: starting $mod:$obj"
      exec gunicorn -b 0.0.0.0:5000 "$mod:$obj"
    fi
  done
  if grep -q "def create_app" "$p"; then
    echo "DeployForge: starting $mod:create_app()"
    exec gunicorn -b 0.0.0.0:5000 "$mod:create_app()"
  fi
done
echo "DeployForge ERROR: Flask app object not found (looked for app, application, create_app in common files)"
exit 1
