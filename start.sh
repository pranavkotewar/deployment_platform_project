#!/bin/bash
echo "Starting Automated Deployment System..."

#1. start Flask backend
cd ~/auto-deploy-system/v1/backend
source venv/bin/activate
python3 app.py > ~/auto-deploy-system/flask.log 2>&1 &
echo "Flask server started (log: flask.log)"

sleep 3

#2. Start ngrok on VM1 for dashboard (Fixed domain)
cd ~/auto-deploy-system
nohup ngrok http --url=https://battered-serpent-yonder.ngrok-free.dev 5000 > ngrok_vm1.log 2>&1 &
echo "ngrok (dashboard) started"

#3. start ngrok on VM2 for the app, remotely via SSH (random domain, port 9000 -> 4041 API)
ssh projectvm2@192.168.42.7 "nohup ngrok http 9000 --log=stdout > ~/ngrok_vm2.log 2>&1 &"
echo "ngrok (app, on VM2) started"

sleep 2

echo ""

echo "Dashboard_URL: https://battered-serpent-yonder.ngrok-free.dev"
echo "Local Dashboard_URL: http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "Done. Use  ./stop.sh to stop everything."
