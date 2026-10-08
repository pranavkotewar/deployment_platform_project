#!/bin/sh
# Node app start karta hai: npm start, nahi to main, nahi to common file names.
cd /app
if node -e "var s=require('./package.json').scripts; process.exit(s && s.start ? 0 : 1)"; then
  echo "DeployForge: npm start"
  exec npm start
fi
main=$(node -p "require('./package.json').main || ''")
for f in "$main" server.js index.js app.js main.js src/index.js; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    echo "DeployForge: node $f"
    exec node "$f"
  fi
done
echo "DeployForge ERROR: no start script and no entry file found"
exit 1
