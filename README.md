# Test App - GitHub Actions Runner with Nix Profile Management

This repository demonstrates a working solution for deploying Nix-built applications via GitHub Actions self-hosted runners, overcoming several complex permission and profile management issues.

## Overview

The test app is a simple Bun server that displays an emoji, used to verify deployments are actually updating the running service. The real value is in the CI/CD pipeline solution that handles Nix profile updates correctly.

## Problems Encountered and Solutions

### Problem 1: Runner couldn't write to `/build` directory
**Issue**: The GitHub Actions runner couldn't write to `/build` because it's a root-owned system directory.

**Solution**: Used the runner's StateDirectory at `/var/lib/github-runner/test-app-runner/builds` which the runner owns and can write to.

### Problem 2: Nix profile upgrades failing silently with git+file:// URLs
**Issue**: When we used `rsync` without excluding `.git`, the build directory contained git metadata. This caused Nix to use `git+file://` URLs in the profile, which broke upgrades because:
- Git URLs are tied to specific commits
- `nix profile upgrade` couldn't upgrade from one git commit to another
- The profile would silently fail to update

**Solution**: Excluded `.git` directory from rsync: `--exclude='.git'`. This made Nix use `path:` URLs instead, which work correctly with upgrades.

### Problem 3: Impure builds with `bun install`
**Issue**: The flake.nix had `bun install` in the buildPhase, making builds impure and potentially inconsistent.

**Solution**: 
- Removed `bun install` from buildPhase (we had no runtime dependencies anyway)
- Enabled `nix.settings.sandbox = true` in the NixOS configuration for pure builds
- Added `touch flake.nix` in CI to bust Nix's eval cache

### Problem 4: Profile permission issues - the core problem
This was the most complex issue with multiple layers:

#### 4a. HOME environment mismatch
**Issue**: The runner runs as user `justin` but with `HOME=/run/github-runner/test-app-runner/` instead of `/home/justin`. This caused Nix commands to look for profiles in the wrong location.

**First attempt**: Set `export HOME=/home/justin` in CI  
**Result**: Failed - runner couldn't write to `/home/justin/.cache/nix`, got "Permission denied"

#### 4b. Profile manifest.json owned by root
**Issue**: The file `/home/justin/.local/state/nix/profiles/profile/manifest.json` was owned by root, preventing the runner from updating justin's profile.

**Attempts**:
1. Tried using `sudo rm` to remove root-owned symlinks - blocked by NoNewPrivileges
2. Tried using explicit `--profile` flag with justin's profile - still hit permission errors
3. Tried creating a dedicated profile at `/home/justin/.local/state/nix/profiles/test-app` - same permission issues

#### 4c. NoNewPrivileges prevents sudo
**Issue**: The GitHub runner service has `NoNewPrivileges=true` in its systemd unit, which completely blocks any use of `sudo`. This prevented:
- Using `sudo -Hiu justin` to run commands as justin with proper environment
- Using `sudo` to fix permission issues
- Using `sudo` to create symlinks in `/home/justin/`

**Final Solution - Runner-owned profile with symlink**:
1. **Created a runner-owned profile**: `/var/lib/github-runner/test-app-runner/profile`
   - Runner can write to this location
   - No permission issues with manifest.json
   
2. **Created a symlink in runner-owned directory**: `/var/lib/github-runner/test-app-runner/bin/test-app`
   - Points to the profile's binary
   - Runner can create/update this symlink without sudo
   
3. **Updated systemd service** to use the new path:
   ```nix
   ExecStart = "/var/lib/github-runner/test-app-runner/bin/test-app";
   ConditionPathExists = "/var/lib/github-runner/test-app-runner/bin/test-app";
   ```

### Problem 5: Profile not actually updating (detection)
**Issue**: Initially, the CI would report success but the profile wasn't actually updating. The service would restart but still run the old version.

**Solution**: Added assertions in CI to verify the profile update:
```bash
if ! nix profile list --profile "$RUNNER_PROFILE" | grep -q test-app; then
  echo "❌ CRITICAL ERROR: test-app not found in runner profile!"
  nix profile list --profile "$RUNNER_PROFILE"
  exit 1
fi
```

## Final Working Solution

The CI workflow now:
1. Syncs code to `/var/lib/github-runner/test-app-runner/builds` (excluding `.git`)
2. Builds with pure Nix (no `bun install`, sandbox enabled)
3. Updates profile at `/var/lib/github-runner/test-app-runner/profile` (runner-owned)
4. Creates/updates symlink at `/var/lib/github-runner/test-app-runner/bin/test-app`
5. Systemd service uses this symlink path
6. Service restarts and picks up the new version

This completely avoids:
- Permission issues (runner owns everything it needs to modify)
- NoNewPrivileges restrictions (no sudo required)
- HOME environment mismatches (uses explicit paths)
- Git URL problems (uses path: URLs)
- Silent failures (has assertions to verify success)

## Key Insights

The key insight was that we couldn't fix the permission model between the runner and justin's profile, so we created a parallel profile structure that the runner fully controls, with the systemd service configured to use it.

## Architecture

```
GitHub Actions Runner (runs as justin with restricted HOME)
    ↓
/var/lib/github-runner/test-app-runner/
    ├── builds/           # Build directory (rsync target)
    ├── profile/          # Nix profile (runner-owned)
    └── bin/
        └── test-app      # Symlink to profile binary

Systemd Service
    ↓
Reads from: /var/lib/github-runner/test-app-runner/bin/test-app
```

## Files

- `.github/workflows/ci.yml` - CI pipeline with all the fixes
- `flake.nix` - Pure Nix build without runtime dependencies
- `src/index.ts` - Simple Bun server showing an emoji
- NixOS configs (in separate repo):
  - `hetzner/test-app.nix` - Systemd service configuration
  - `hetzner/configuration.nix` - Enables sandbox for pure builds
  - `hetzner/github-runner-test-app.nix` - Runner configuration

## Testing

The solution has been verified to work repeatedly:
1. Change the emoji in `src/index.ts`
2. Commit and push
3. Trigger CI with `gh workflow run ci.yml`
4. Verify the new emoji appears at http://YOUR_SERVER:3001

## Requirements

- NixOS with systemd
- GitHub Actions self-hosted runner
- Bun runtime
- Polkit rules for service restart (without sudo)