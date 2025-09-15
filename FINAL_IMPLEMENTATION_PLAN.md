# Final Implementation Plan: Solving GitHub Runner Directory Permissions

## Executive Summary

Both `slipbox` and `test-app` GitHub runners **cannot write to `/build`** despite various systemd configuration attempts. This document consolidates all findings and proposes a working solution.

## The Core Problem

1. **Slipbox CI is broken**: Cannot write to `/build` even with `ProtectSystem=false` and `ReadWritePaths=["/build"]`
2. **Test-app reproduces the issue**: Created as minimal reproduction (see `minimal-reproduction-prompt.md`)
3. **Root cause**: GitHub runners operate in a restricted environment that prevents writing outside specific directories, regardless of systemd settings

For detailed investigation history, see `IMPLEMENTATION_REPORT.md` (Sessions 1-3)

## Key Findings

### What Doesn't Work
- ❌ Writing to `/build` (even with ReadWritePaths)
- ❌ Setting `ProtectSystem=false` (slipbox has this, still fails)
- ❌ Using restart triggers (requires nixos-rebuild which CI can't run)
- ❌ Polkit without proper directory access (solved auth, not directory issue)

### What Does Work
- ✅ Polkit for systemctl restart (no sudo needed)
- ✅ Writing to `/run/github-runner/<runner-name>/` (RuntimeDirectory)
- ✅ Writing to `/var/lib/github-runner/<runner-name>/` (StateDirectory)
- ✅ Writing to runner's working directory

### Critical Discovery
The GitHub runner can ONLY write to:
1. Its RuntimeDirectory (`/run/github-runner/<runner-name>/`)
2. Its StateDirectory (`/var/lib/github-runner/<runner-name>/`)
3. Its working directory (ephemeral, changes between runs)
4. Possibly `/tmp` (if PrivateTmp is set)

## The Solution: Use StateDirectory

### Why StateDirectory?
- **Persistent**: Survives reboots and service restarts
- **Writable**: Always writable even with `ProtectSystem=strict`
- **Consistent path**: `/var/lib/github-runner/<runner-name>/builds`
- **Already configured**: No additional systemd changes needed
- **Secure**: Isolated per runner

### Implementation for test-app

```yaml
# .github/workflows/ci.yml
- name: Deploy to production
  run: |
    # Use StateDirectory for consistent builds
    BUILD_DIR="/var/lib/github-runner/test-app-runner/builds"
    mkdir -p "$BUILD_DIR"
    
    # Clean and sync to build directory
    rm -rf "$BUILD_DIR"/*
    rsync -av --exclude='.git' --exclude='node_modules' --exclude='result' . "$BUILD_DIR"/
    cd "$BUILD_DIR"
    
    # Build and install from consistent location
    nix build .#test-app
    nix profile remove test-app 2>/dev/null || true
    nix profile install .#test-app
    
    # Restart using polkit (already working)
    systemctl restart test-app
```

### Implementation for slipbox

```yaml
# Similar pattern, using slipbox runner's StateDirectory
BUILD_DIR="/var/lib/github-runner/hetzner-runner/builds"
```

## Why Previous Attempts Failed

1. **`/build` directory**: GitHub runners run in a mount namespace that makes /build read-only regardless of permissions
2. **Restart triggers**: Only work during `nixos-rebuild switch`, not from CI
3. **Sudo approach**: NoNewPrivileges flag prevents sudo from working
4. **Inconsistent paths**: Nix profile couldn't recognize packages to upgrade

## Configuration Requirements

### Already Completed
- ✅ Polkit rules for systemctl restart
- ✅ GitHub runner with necessary packages (git, gh, curl, rsync)
- ✅ Runner token configured

### Still Needed
- No NixOS changes required! StateDirectory already exists and is writable

## Testing Plan

1. Update test-app CI to use StateDirectory
2. Push change and verify:
   - Build succeeds in StateDirectory
   - Nix profile upgrades correctly
   - Service restarts via polkit
   - New version deploys successfully
3. Apply same pattern to slipbox

## Alternative Approaches (if StateDirectory fails)

### Option A: RuntimeDirectory
- Use `/run/github-runner/<runner-name>/builds`
- Pros: Always writable
- Cons: Cleared on reboot (but nix store persists)

### Option B: Home directory workaround
- Create symlink from StateDirectory to a "fake" /build
- Might trick the system but adds complexity

### Option C: Custom systemd service
- Create separate build service with different permissions
- Overly complex for the problem

## Files to Update

1. **test-app/.github/workflows/ci.yml**: Use StateDirectory for builds
2. **slipbox/.github/workflows/ci.yml**: Apply same pattern
3. **IMPLEMENTATION_REPORT.md**: Document final solution

## Success Criteria

- [ ] CI can build in a consistent directory
- [ ] Nix profile recognizes and upgrades packages
- [ ] Service restarts automatically via polkit
- [ ] No sudo required
- [ ] No NixOS redeployment needed

## Conclusion

The solution is simpler than expected: **Use the runner's StateDirectory** which is already writable and persistent. This avoids fighting systemd's security model and works within the constraints of the GitHub runner environment.

The key insight: Stop trying to write to `/build` and use the directories that systemd explicitly makes available to the service.
