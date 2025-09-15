#!/bin/bash
set -e

echo "=== Test App Deployment Script ==="
echo ""
echo "This script will help you deploy the test app to your NixOS server."
echo ""

# Step 1: Initialize git and push to GitHub
if [ ! -d .git ]; then
  echo "Step 1: Initializing git repository..."
  git init
  git add .
  git commit -m "Initial test app for debugging runner permissions"
  echo ""
  echo "Creating GitHub repository..."
  gh repo create test-app --private --source=. --remote=origin --push
else
  echo "Step 1: Git repository already initialized, skipping..."
fi

# Step 2: Build the app locally
echo ""
echo "Step 2: Building the app with Nix..."
nix build .#test-app

# Step 3: Initial deployment to server
echo ""
echo "Step 3: Deploying to server..."
echo "Syncing files to server..."
rsync -av --exclude='.git' --exclude='result' . justin@135.181.179.143:/tmp/test-app/

echo ""
echo "Installing on server..."
ssh justin@135.181.179.143 "cd /tmp/test-app && nix profile remove test-app 2>/dev/null || true && nix profile install .#test-app"

echo ""
echo "=== IMPORTANT: Manual Steps Required ==="
echo ""
echo "1. Create the GitHub runner token:"
echo "   - Go to: https://github.com/justinmoon/test-app/settings/actions/runners"
echo "   - Click 'New self-hosted runner'"
echo "   - Copy the token (starts with AAAA...)"
echo ""
echo "2. Add the token to the server:"
echo "   ssh justin@135.181.179.143"
echo "   sudo bash -c 'echo YOUR_TOKEN_HERE > /var/lib/github-runner-test-app-token'"
echo "   sudo chmod 600 /var/lib/github-runner-test-app-token"
echo ""
echo "3. Deploy the NixOS configuration:"
echo "   cd ~/configs"
echo "   git add hetzner/test-app.nix hetzner/polkit-rules.nix hetzner/github-runner-multi.nix"
echo "   git add hetzner/configuration.nix  # with the updated imports"
echo "   git commit -m 'Add test-app service and polkit rules'"
echo "   git push origin master"
echo "   just hetzner  # This deploys the config to the server"
echo ""
echo "4. Start the service manually (first time):"
echo "   ssh justin@135.181.179.143"
echo "   sudo systemctl start test-app"
echo "   systemctl status test-app"
echo ""
echo "5. Test the deployment:"
echo "   curl http://slipbox.xyz:3001"
echo ""
echo "6. Test CI by changing the emoji:"
echo "   Edit src/index.ts and change the emoji from 🚀 to something else"
echo "   git add -A && git commit -m 'Test deployment' && git push"
echo "   Watch the GitHub Actions run!"
echo ""
echo "=== Success Criteria ==="
echo "The GitHub Actions should be able to run:"
echo "  systemctl restart test-app  # Without sudo, using polkit!"
echo ""