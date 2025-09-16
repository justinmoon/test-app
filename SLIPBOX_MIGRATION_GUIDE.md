# Slipbox Migration Guide

Based on our successful test-app implementation with dependencies, here's how to apply these solutions to Slipbox:

## Key Learnings from Test App

1. **Dependencies in Pure Builds**: We successfully handled bun dependencies by:
   - Running `bun install` in CI before `nix build`
   - Having the Nix derivation use the pre-installed `node_modules`
   - Keeping sandbox enabled for pure builds

2. **Profile Management**: Runner-owned profile structure works perfectly:
   - Profile at: `/var/lib/github-runner/slipbox-runner/profile`
   - Symlink at: `/var/lib/github-runner/slipbox-runner/bin/slipbox`
   - Systemd reads from the symlink

## Step-by-Step Migration for Slipbox

### 1. Update Slipbox CI Workflow

```yaml
# .github/workflows/ci.yml
- name: Deploy to production
  run: |
    # Use runner's StateDirectory instead of /build
    BUILD_DIR="/var/lib/github-runner/slipbox-runner/builds"
    rm -rf "$BUILD_DIR"/*
    rm -rf "$BUILD_DIR"/.??* 2>/dev/null || true
    
    # Exclude .git to avoid git+file:// URLs
    rsync -av --exclude='node_modules' --exclude='result' --exclude='.git' . "$BUILD_DIR"/
    cd "$BUILD_DIR"
    
    # Touch to bust cache
    touch flake.nix
    
    # Install dependencies BEFORE nix build
    echo "Installing dependencies..."
    bun install --frozen-lockfile
    
    # Build the application
    echo "Building slipbox..."
    nix build .#slipbox
    
    # Use runner-owned profile
    RUNNER_PROFILE="/var/lib/github-runner/slipbox-runner/profile"
    
    # Update profile
    if nix profile list --profile "$RUNNER_PROFILE" | grep -q slipbox; then
      nix profile upgrade --profile "$RUNNER_PROFILE" slipbox
    else
      nix profile install --profile "$RUNNER_PROFILE" .#slipbox
    fi
    
    # Create/update symlink
    SYMLINK_DIR="/var/lib/github-runner/slipbox-runner/bin"
    mkdir -p "$SYMLINK_DIR"
    ln -sf "$RUNNER_PROFILE/bin/slipbox" "$SYMLINK_DIR/slipbox"
    
    # Restart service
    systemctl restart slipbox
```

### 2. Update Slipbox flake.nix

```nix
# Remove __noChroot = true; (incompatible with sandbox)
# Remove bun install from buildPhase
# Expect node_modules to exist from CI

buildPhase = ''
  # Copy source files
  cp -r $src/* .
  chmod -R u+w .
  
  # node_modules should exist from CI's bun install
  if [ ! -d "node_modules" ]; then
    echo "WARNING: node_modules not found"
    echo "Run 'bun install' before 'nix build'"
  fi
  
  # Build client assets
  bun run build:client
  
  # Any other build steps...
'';

installPhase = ''
  mkdir -p $out/app
  mkdir -p $out/bin
  
  # Copy app files including node_modules
  cp -r src $out/app/
  cp -r dist $out/app/
  cp -r static $out/app/ 2>/dev/null || true
  cp -r node_modules $out/app/
  cp package.json $out/app/
  cp bun.lock $out/app/
  
  # Wrapper script
  cat > $out/bin/slipbox <<EOF
  #!/usr/bin/env bash
  cd $out/app
  exec ${pkgs.bun}/bin/bun run src/index.ts "\$@"
  EOF
  chmod +x $out/bin/slipbox
'';
```

### 3. Update NixOS Service Configuration

```nix
# hetzner/slipbox.nix
systemd.services.slipbox = {
  serviceConfig = {
    # Change from justin's profile to runner's symlink
    ExecStart = "/var/lib/github-runner/slipbox-runner/bin/slipbox";
    # Keep other settings the same
  };
  
  unitConfig = {
    # Update condition path
    ConditionPathExists = "/var/lib/github-runner/slipbox-runner/bin/slipbox";
  };
};
```

### 4. Update GitHub Runner Configuration

```nix
# hetzner/github-runner.nix (or similar)
services.github-runners.slipbox-runner = {
  # Add bun to packages
  extraPackages = with pkgs; [
    git
    gh
    curl
    rsync
    bun  # CRITICAL: Add this for dependency installation
    # ... other packages
  ];
};
```

### 5. Handle Slipbox-Specific Build Steps

Slipbox has additional complexity:
- **Tailwind CSS build**: `bun run build:client` needs to run with node_modules
- **TypeScript**: Already handled by bun
- **Database migrations**: Run these after deployment if needed

## Migration Checklist

- [ ] Update `.github/workflows/ci.yml` to use runner's StateDirectory
- [ ] Add `bun install` step before `nix build` in CI
- [ ] Update `flake.nix` to remove `__noChroot` and `bun install`
- [ ] Update `hetzner/slipbox.nix` to use runner's symlink path
- [ ] Add `bun` to runner's extraPackages
- [ ] Deploy NixOS configuration
- [ ] Test deployment with a small change
- [ ] Verify Tailwind CSS builds correctly
- [ ] Verify app runs with all dependencies

## Benefits of This Approach

1. **Pure Builds**: Works with `sandbox = true`
2. **No Permission Issues**: Runner owns everything it needs
3. **Reproducible**: Dependencies locked with `bun.lock`
4. **Fast**: Dependencies cached between builds
5. **Simple**: No complex FOD (fixed-output derivation) hashing

## Potential Issues and Solutions

### Issue: Build fails without network
**Solution**: Dependencies must be installed in CI before nix build

### Issue: node_modules too large
**Solution**: Consider pruning dev dependencies after build:
```bash
bun install --frozen-lockfile
bun run build:client
bun install --production  # Remove dev deps
```

### Issue: Binary dependencies
**Solution**: May need to rebuild native modules:
```bash
bun install --frozen-lockfile
bun rebuild  # Rebuild native modules
```

## Testing the Migration

1. Start with a branch: `fix-slipbox-deployment`
2. Make incremental changes and test each:
   - First: Just change build directory
   - Then: Add dependency installation
   - Finally: Switch to runner profile
3. Monitor CI logs carefully
4. Test app functionality after each deployment

## Rollback Plan

If issues arise:
1. Revert CI workflow changes
2. Keep using current deployment method
3. Debug specific issues one at a time

The key insight is that we don't need complex fixed-output derivations or vendored dependencies. We just need to:
1. Install dependencies in CI (outside Nix sandbox)
2. Let Nix build use those dependencies
3. Use runner-owned paths to avoid permission issues