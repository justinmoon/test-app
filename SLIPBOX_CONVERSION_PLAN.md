# Slipbox CI/CD Conversion Plan - Fixed-Output Derivation Pattern

## Overview

This plan converts Slipbox from the current non-deterministic CI pattern to a fully deterministic Fixed-Output Derivation (FOD) approach, ensuring reproducible builds with proper dependency management.

## Current State Analysis

### Problems with Current Slipbox Setup
1. Uses `/build/slipbox` directory (permission issues)
2. Runs `bun install` in impure Nix derivation 
3. Profile permission issues with justin's profile
4. Non-deterministic builds
5. Tests disabled in CI

### Current Files to Modify
- `/Users/justin/code/slipbox/.github/workflows/ci.yml`
- `/Users/justin/code/slipbox/flake.nix`
- `/Users/justin/configs/hetzner/slipbox.nix`
- `/Users/justin/configs/hetzner/github-runner.nix` (or create new `github-runner-slipbox.nix`)

## Step-by-Step Conversion Plan

### Phase 1: Update Slipbox flake.nix for FOD

#### 1.1 Create Fixed-Output Derivation for Dependencies

```nix
# In slipbox/flake.nix
bunDeps = pkgs.stdenv.mkDerivation {
  pname = "slipbox-deps";
  version = "1.0.0";
  
  # Only files that determine dependencies
  src = pkgs.runCommand "dep-src" {} ''
    mkdir -p $out
    cp ${./package.json} $out/package.json
    cp ${./bun.lock} $out/bun.lock
  '';
  
  nativeBuildInputs = [ pkgs.bun pkgs.cacert ];
  
  buildPhase = ''
    cp $src/* .
    export HOME=$TMPDIR
    
    # Install all dependencies with locked versions
    bun install --frozen-lockfile --no-progress --no-summary
    
    # Clean up cache
    rm -rf $HOME/.bun
  '';
  
  installPhase = ''
    mkdir -p $out
    cp -r node_modules $out/
    cp bun.lock $out/
  '';
  
  # Fixed-output settings
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = pkgs.lib.fakeHash; # Will be replaced with actual hash
};
```

#### 1.2 Update Main Package to Use FOD

```nix
slipbox = pkgs.stdenv.mkDerivation {
  pname = "slipbox";
  version = "1.0.0";
  
  src = ./.;
  
  nativeBuildInputs = with pkgs; [
    bun
    nodejs_20
  ];
  
  buildPhase = ''
    # Copy source files
    cp -r $src/src .
    cp -r $src/scripts .
    cp -r $src/static . 2>/dev/null || true
    cp $src/package.json .
    cp $src/tsconfig.json .
    cp $src/tailwind.config.js . 2>/dev/null || true
    cp $src/postcss.config.js . 2>/dev/null || true
    cp $src/biome.json . 2>/dev/null || true
    
    # Link dependencies from FOD
    ln -s ${bunDeps}/node_modules node_modules
    
    # Verify critical dependencies
    test -d node_modules/@starfederation/datastar || exit 1
    test -d node_modules/tailwindcss || exit 1
    
    # Build client assets (Tailwind CSS)
    echo "Building client assets..."
    bun run build:client
    
    # TypeScript check (optional, remove if slow)
    # bun run typecheck
  '';
  
  installPhase = ''
    mkdir -p $out/app $out/bin
    
    # Copy built application
    cp -r src $out/app/
    cp -r dist $out/app/
    cp -r static $out/app/ 2>/dev/null || true
    cp -r scripts $out/app/
    cp -r ${bunDeps}/node_modules $out/app/node_modules
    cp package.json $out/app/
    cp tsconfig.json $out/app/
    cp bun.lock $out/app/
    
    # Create wrapper script
    cat > $out/bin/slipbox <<EOF
    #!/usr/bin/env bash
    cd $out/app
    export NODE_ENV=\''${NODE_ENV:-production}
    export SLIPBOX_DATA_DIR=\''${SLIPBOX_DATA_DIR:-/var/lib/slipbox}
    export PORT=\''${PORT:-3000}
    exec ${pkgs.bun}/bin/bun run src/index.ts "\$@"
    EOF
    chmod +x $out/bin/slipbox
  '';
};
```

#### 1.3 Get the Actual Hash

```bash
# From slipbox directory
cd ~/code/slipbox

# Build deps to get hash
nix build .#deps 2>&1 | grep "got:" | cut -d: -f2 | xargs

# Update flake.nix with the actual hash
# outputHash = "sha256-ACTUAL_HASH_HERE";
```

### Phase 2: Create Dedicated GitHub Runner for Slipbox

#### 2.1 Create github-runner-slipbox.nix

```nix
# ~/configs/hetzner/github-runner-slipbox.nix
{ config, pkgs, lib, ... }:

{
  services.github-runners = {
    slipbox-runner = {
      enable = true;
      name = "slipbox-runner";
      url = "https://github.com/justinmoon/slipbox";
      tokenFile = "/var/lib/github-runner-slipbox-token";
      user = "justin";
      extraLabels = [ "self-hosted" ];
      
      # All packages needed for slipbox
      extraPackages = with pkgs; [
        git
        gh              # For auto-merge
        curl
        rsync
        bun             # For potential debugging
        nodejs_20       # For potential debugging
        systemd         # For systemctl
        playwright-driver.browsers  # For tests
      ];
      
      # Environment for playwright tests
      serviceOverrides = {
        Environment = [
          "PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}"
          "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1"
        ];
      };
    };
  };
}
```

#### 2.2 Update hetzner/configuration.nix

```nix
# Add to imports
imports = [
  # ... existing imports ...
  ./github-runner-test-app.nix     # Keep for now
  ./github-runner-slipbox.nix      # New slipbox runner
];
```

### Phase 3: Update CI Workflow

#### 3.1 New .github/workflows/ci.yml

```yaml
name: CI

on:
  workflow_dispatch:
  pull_request:
    branches: [master, main]

jobs:
  test-and-deploy:
    runs-on: self-hosted

    permissions:
      contents: write
      pull-requests: write
      checks: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run tests
        run: |
          echo "Building test version..."
          nix build .#slipbox
          
          # Run playwright tests if enabled
          # export PLAYWRIGHT_BROWSERS_PATH="${{ env.PLAYWRIGHT_BROWSERS_PATH }}"
          # nix run .#ci

      - name: Deploy to production
        if: success()
        run: |
          # Runner's StateDirectory
          BUILD_DIR="/var/lib/github-runner/slipbox-runner/builds"
          echo "Using build directory: $BUILD_DIR"
          mkdir -p "$BUILD_DIR"
          
          # Get git commit for version tracking
          export GIT_COMMIT=$(git rev-parse --short HEAD)
          
          # Clean and sync to build directory
          echo "Syncing to build directory..."
          rm -rf "$BUILD_DIR"/*
          rm -rf "$BUILD_DIR"/.??* 2>/dev/null || true
          # CRITICAL: Exclude .git to avoid git+file:// URLs
          rsync -av --exclude='node_modules' --exclude='result' --exclude='.git' . "$BUILD_DIR"/
          cd "$BUILD_DIR"
          
          # Touch flake.nix to bust Nix eval cache
          touch flake.nix
          
          # Build with Nix (uses FOD for dependencies)
          echo "Building slipbox version: $GIT_COMMIT"
          nix build .#slipbox
          
          # Update runner-owned profile
          RUNNER_PROFILE="/var/lib/github-runner/slipbox-runner/profile"
          echo "Using runner profile: $RUNNER_PROFILE"
          
          # Check current profile
          echo "Current profile contents:"
          nix profile list --profile "$RUNNER_PROFILE" | grep slipbox || echo "No slipbox in profile"
          
          # Update or install
          if nix profile list --profile "$RUNNER_PROFILE" 2>/dev/null | grep -E 'slipbox' > /dev/null; then
            echo 'Slipbox found in profile, upgrading...'
            nix profile upgrade --profile "$RUNNER_PROFILE" slipbox || {
              echo '⚠️ Upgrade failed, removing and reinstalling...'
              nix profile remove --profile "$RUNNER_PROFILE" slipbox
              nix profile install --profile "$RUNNER_PROFILE" .#slipbox
            }
          else
            echo 'Slipbox not in profile, installing...'
            nix profile install --profile "$RUNNER_PROFILE" .#slipbox
          fi
          
          # Verify installation
          if ! nix profile list --profile "$RUNNER_PROFILE" | grep -q slipbox; then
            echo "❌ ERROR: slipbox not found in profile!"
            exit 1
          fi
          
          echo "✅ Slipbox installed in runner's profile"
          
          # Create/update symlink for systemd
          SYMLINK_DIR="/var/lib/github-runner/slipbox-runner/bin"
          mkdir -p "$SYMLINK_DIR"
          ln -sf "$RUNNER_PROFILE/bin/slipbox" "$SYMLINK_DIR/slipbox"
          echo "Symlink created: $SYMLINK_DIR/slipbox"
          
          # Restart service
          echo "Restarting slipbox service..."
          systemctl restart slipbox
          
          echo "Checking service status..."
          systemctl status slipbox --no-pager || true
          
          # Test endpoint
          sleep 3
          curl -s http://localhost:3000 | grep -q "Slipbox" && echo "✅ Slipbox is running" || echo "❌ Failed to verify"

      - name: Auto-merge PR
        if: |
          success() && 
          github.event_name == 'pull_request' && 
          github.event.pull_request.user.login == github.repository_owner
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "All tests passed! Merging PR #${{ github.event.pull_request.number }}"
          gh pr merge ${{ github.event.pull_request.number }} \
            --repo ${{ github.repository }} \
            --squash \
            --delete-branch
```

### Phase 4: Update NixOS Service Configuration

#### 4.1 Update hetzner/slipbox.nix

```nix
{ config, pkgs, lib, ... }:

let
  slipboxUser = "justin";
  slipboxGroup = "users";
  slipboxPort = 3000;
  slipboxDataDir = "/var/lib/slipbox";
in
{
  # Create directory structure
  systemd.tmpfiles.rules = [
    "d ${slipboxDataDir} 0750 ${slipboxUser} ${slipboxGroup} -"
  ];

  systemd.services.slipbox = {
    description = "Slipbox App";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = slipboxUser;
      Group = slipboxGroup;
      WorkingDirectory = slipboxDataDir;
      
      # Use runner's symlink instead of justin's profile
      ExecStart = "/var/lib/github-runner/slipbox-runner/bin/slipbox";
      
      Restart = "always";
      RestartSec = "10s";
      
      Environment = [
        "NODE_ENV=production"
        "SLIPBOX_DATA_DIR=${slipboxDataDir}"
        "PORT=${toString slipboxPort}"
      ];
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = false;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ slipboxDataDir "/tmp" ];
      
      # Resource limits
      MemoryMax = "512M";
      CPUQuota = "100%";
    };
    
    unitConfig = {
      # Update to use runner's symlink
      ConditionPathExists = "/var/lib/github-runner/slipbox-runner/bin/slipbox";
    };
  };

  # Keep existing firewall, backup, and helper scripts...
}
```

## Migration Checklist

### Pre-Migration Preparation
- [ ] Backup current slipbox data: `rsync -av justin@server:/var/lib/slipbox ~/slipbox-backup/`
- [ ] Test build locally: `cd ~/code/slipbox && nix build .#slipbox`
- [ ] Document current hash for rollback

### Phase 1: Update Slipbox Code
- [ ] Update `flake.nix` with FOD pattern
- [ ] Build deps locally to get hash: `nix build .#deps`
- [ ] Update hash in flake.nix
- [ ] Test full build: `nix build .#slipbox`
- [ ] Commit changes to a branch: `fix-slipbox-deployment`

### Phase 2: Deploy Runner Configuration
- [ ] Create `github-runner-slipbox.nix`
- [ ] Add to `configuration.nix` imports
- [ ] Deploy: `cd ~/configs && just hetzner`
- [ ] Setup runner token: `ssh justin@server 'echo "YOUR_TOKEN" | sudo tee /var/lib/github-runner-slipbox-token'`
- [ ] Verify runner is online in GitHub settings

### Phase 3: Update CI Workflow
- [ ] Update `.github/workflows/ci.yml`
- [ ] Commit and push to PR
- [ ] Watch CI run for issues

### Phase 4: Update Service Configuration
- [ ] Update `hetzner/slipbox.nix`
- [ ] Deploy: `cd ~/configs && just hetzner`
- [ ] Verify service restarts with new path

### Phase 5: Testing and Validation
- [ ] Trigger test deployment via PR
- [ ] Check service status: `ssh justin@server 'systemctl status slipbox'`
- [ ] Test application: `curl http://slipbox.xyz`
- [ ] Monitor logs: `ssh justin@server 'journalctl -u slipbox -f'`
- [ ] Verify data persistence in `/var/lib/slipbox`

### Post-Migration Cleanup
- [ ] Once stable, remove test-app runner
- [ ] Remove old runner configurations
- [ ] Document the new setup

## Rollback Plan

If issues occur:

1. **Quick rollback** (keeps new runner):
   ```bash
   # On server
   ssh justin@server
   cd /var/lib/github-runner/slipbox-runner/builds
   git checkout main  # Or last known good
   nix profile install .#slipbox --profile /var/lib/github-runner/slipbox-runner/profile
   systemctl restart slipbox
   ```

2. **Full rollback** (reverts everything):
   ```bash
   # Revert configs
   cd ~/configs
   git revert HEAD  # Or checkout previous commit
   just hetzner
   
   # Revert slipbox
   cd ~/code/slipbox
   git checkout main
   ```

## Key Differences from Test-App

1. **More complex build**:
   - Tailwind CSS compilation (`bun run build:client`)
   - TypeScript files
   - Static assets
   - Database migrations (handled separately)

2. **Larger dependency tree**:
   - FOD hash will be bigger
   - Initial build will take longer
   - But subsequent builds will be cached

3. **Production considerations**:
   - Data directory must be preserved
   - Backup scripts must continue working
   - Database migrations may need manual run

## Success Criteria

- [ ] Deployments are deterministic
- [ ] CI passes reliably
- [ ] Service restarts successfully
- [ ] No data loss
- [ ] Rollback is possible
- [ ] Build times are reasonable (< 2 min)
- [ ] Tests can run in CI (if re-enabled)

## Debugging Strategies

### Test Directly on Server First
```bash
# SSH to server and test WITHOUT CI
ssh justin@135.181.179.143
cd /var/lib/github-runner/slipbox-runner/builds
rsync -av --exclude='.git' --exclude='node_modules' justin@local:/code/slipbox/ .
nix build .#slipbox
nix profile install --profile /var/lib/github-runner/slipbox-runner/profile .#slipbox

# Only after this works, test via CI
```

### Debug FOD Hash Issues
```bash
# When hash mismatches occur
nix build .#deps 2>&1 | grep "got:" | cut -d: -f2 | xargs
# Copy hash immediately to flake.nix
```

### Test Without Systemd
```bash
# Run directly to see errors
/var/lib/github-runner/slipbox-runner/bin/slipbox
# Check it starts before dealing with systemd
```

### Profile Debugging
```bash
# Check profile ownership issues
ls -la /home/justin/.local/state/nix/profiles/
ls -la /var/lib/github-runner/slipbox-runner/
stat -c %U:%G /path/to/manifest.json
```

### CI Debugging
```bash
# Watch logs in real-time
gh run watch <run-id>
gh run view <run-id> --log-failed | less

# Run CI steps manually on server
ssh justin@server
sudo -u justin bash  # Simulate runner user
cd /var/lib/github-runner/slipbox-runner/builds
# Paste CI commands one by one
```

### Quick Iteration
```bash
# Skip CI entirely during debugging
ssh justin@server "cd /path && nix build && systemctl restart slipbox"
# Much faster than waiting for CI
```

## Timeline Estimate

- Phase 1 (Update flake): 30 minutes
- Phase 2 (Setup runner): 20 minutes
- Phase 3 (Update CI): 15 minutes
- Phase 4 (Update service): 15 minutes
- Phase 5 (Testing): 30 minutes
- Buffer for issues: 30 minutes

**Total: ~2-3 hours**

## Notes

- Keep test-app runner until slipbox is stable
- Consider enabling tests once deployment is stable
- FOD hash must be updated when dependencies change
- Document hash update process for future maintainers