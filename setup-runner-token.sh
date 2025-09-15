#!/bin/bash

# GitHub Runner Token Setup Script
# This script configures the GitHub runner token on the NixOS server

TOKEN="ABBCQBO7H2NX5L4KP3SSGSTIZBVPA"
SERVER="justin@135.181.179.143"
TOKEN_FILE="/var/lib/github-runner-test-app-token"

echo "Setting up GitHub runner token for test-app..."

# Create the token file on the server
ssh $SERVER "sudo bash -c 'echo $TOKEN > $TOKEN_FILE && chmod 600 $TOKEN_FILE'"

if [ $? -eq 0 ]; then
    echo "✓ Token file created successfully"
else
    echo "✗ Failed to create token file"
    exit 1
fi

# Restart the runner service to pick up the new token
echo "Restarting GitHub runner service..."
ssh $SERVER "sudo systemctl restart github-runner-test-app-runner"

if [ $? -eq 0 ]; then
    echo "✓ Runner service restarted"
else
    echo "✗ Failed to restart runner service"
    echo "The service might not exist yet. Deploy NixOS config first."
    exit 1
fi

# Check the status
echo ""
echo "Checking runner status..."
ssh $SERVER "sudo systemctl status github-runner-test-app-runner --no-pager | head -20"

echo ""
echo "Setup complete! The runner should now be registered with GitHub."
echo "You can verify at: https://github.com/justinmoon/test-app/settings/actions/runners"