#!/bin/bash
echo "Stopping everything..."

pkill -9 -f "app.py"
pkill -9 -f "ngrok"
ssh projectvm2@192.168.42.7 "pkill -9 -f ngrok"

echo "Stopped."
