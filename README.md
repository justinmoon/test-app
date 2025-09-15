# Test App - NixOS GitHub Runner Permissions Debug

This is a minimal Bun application designed to debug and solve GitHub Actions runner permission issues when deploying to NixOS with systemd services.

## Problem Statement

GitHub Actions runners on NixOS with `NoNewPrivileges=true` cannot restart systemd services even with sudo permissions. This test app helps find a solution using polkit.

## Architecture

- **Port**: 3001
- **Service**: Displays an emoji (currently 🚀) to verify deployments
- **Binary Location**: `/home/justin/.nix-profile/bin/test-app`

## Quick Start

### Local Development
```bash
bun install
bun run dev
# Visit http://localhost:3001
```

### Build with Nix
```bash
nix build .#test-app
./result/bin/test-app
```

## Deployment Process

1. **Initial Setup** (one-time):
```bash
# Push to GitHub
git init
git add .
git commit -m "Initial test app"
gh repo create test-app --private --source=. --remote=origin --push

# Initial deployment to server
nix build .#test-app
rsync -av --exclude='.git' . justin@135.181.179.143:/tmp/test-app/
ssh justin@135.181.179.143 "cd /tmp/test-app && nix profile install .#test-app"
ssh justin@135.181.179.143 "sudo systemctl start test-app"
```

2. **CI Deployment** (automatic on push to main):
- GitHub Actions builds the Nix derivation
- Updates the nix profile
- Attempts to restart service using polkit (no sudo)

## Testing a Deployment

Change the emoji in `src/index.ts`:
```typescript
<div class="emoji">🎉</div>  // Change this emoji
```

Commit and push:
```bash
git add -A
git commit -m "Update emoji"
git push
```

Check deployment:
```bash
curl http://slipbox.xyz:3001
```

## Key Files

### Server Configuration Files
- `~/configs/hetzner/test-app.nix` - NixOS service definition
- `~/configs/hetzner/polkit-rules.nix` - Polkit rules for passwordless service restart
- `~/configs/hetzner/github-runner.nix` - GitHub runner configuration

### Application Files
- `src/index.ts` - Bun HTTP server
- `flake.nix` - Nix build configuration
- `.github/workflows/ci.yml` - GitHub Actions workflow

## Solution Approach

The key innovation is using **polkit** instead of sudo to allow the GitHub runner to restart services without hitting the `NoNewPrivileges` restriction.

Example polkit rule:
```javascript
polkit.addRule(function(action, subject) {
  if (action.id == "org.freedesktop.systemd1.manage-units" &&
      action.lookup("unit") == "test-app.service" &&
      subject.user == "justin") {
    return polkit.Result.YES;
  }
});
```

## Success Criteria

The GitHub Actions workflow should successfully run:
```bash
systemctl restart test-app  # Without sudo!
```

## Troubleshooting

If polkit doesn't work, alternative approaches:
1. `systemd.services.<name>.restartTriggers` - Auto-restart on profile changes
2. Systemd path units - Watch profile symlink
3. Capabilities instead of sudo/polkit

## Current Status

- [x] Minimal Bun app created
- [x] Nix flake configured  
- [x] GitHub Actions workflow set up
- [x] NixOS service configured (`~/configs/hetzner/test-app.nix`)
- [x] Polkit rules implemented (`~/configs/hetzner/polkit-rules.nix`)
- [x] GitHub runner updated for multiple repos (`~/configs/hetzner/github-runner-multi.nix`)
- [ ] Configuration deployed to server
- [ ] Solution verified working

## Quick Deploy

Run the deployment script:
```bash
./deploy.sh
```

Then follow the manual steps printed by the script.
