#!/bin/bash

# NixOS Configuration Deployment Script
# This script deploys the test-app configuration to the server

echo "Deploying NixOS configuration for test-app..."
echo ""

# Navigate to configs directory
cd ~/configs || exit 1

# Check current status
echo "Current git status in configs repo:"
git status --short
echo ""

# Stage the new files
echo "Adding new configuration files..."
git add hetzner/test-app.nix hetzner/github-runner-test-app.nix hetzner/polkit-rules.nix
git add hetzner/configuration.nix  # This was modified to include the new modules

# Show what we're about to commit
echo ""
echo "Files to be committed:"
git diff --cached --name-only
echo ""

# Commit the changes
echo "Committing configuration..."
git commit -m "Add test-app service with GitHub runner and sudo rules

- test-app.nix: Service configuration with restart triggers
- github-runner-test-app.nix: Runner with sudo rules and required packages
- polkit-rules.nix: Polkit rules (not used but kept for reference)
- configuration.nix: Import new modules"

# Push to repository
echo ""
echo "Pushing to repository..."
git push origin master

# Deploy to server
echo ""
echo "Deploying to Hetzner server..."
echo "Running: just hetzner"
just hetzner

echo ""
echo "Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Check runner status: ssh justin@135.181.179.143 'sudo systemctl status github-runner-test-app-runner'"
echo "2. Trigger CI: gh workflow run CI --ref fix/restart-triggers"
echo "3. Monitor: gh run watch"