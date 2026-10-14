#!/bin/bash
# DeployForge start: services boot par khud chalti hain; ye haath se start karne ke liye hai
sudo systemctl start deployforge-web deployforge-funnel
./status.sh
