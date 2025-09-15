# Implementation Report: NixOS GitHub Runner Permissions Test App

**Date:** September 15, 2025  
**Last Updated:** September 15, 2025 (Session 2)
**Status:** Solution Identified - Sudo approach confirmed, awaiting deployment

## What Was Completed

### 1. Test Application (/Users/justin/code/test-app)
✅ **Created minimal Bun HTTP server** (`src/index.ts`)
- Runs on port 3001
- Displays emoji (🚀) for easy visual verification of deployments
- Successfully accessible at http://135.181.179.143:3001

✅ **Nix flake configuration** (`flake.nix`)
- Builds Bun app into Nix derivation
- Creates wrapper script that runs with Bun
- Successfully installs to `/home/justin/.nix-profile/bin/test-app`

✅ **GitHub Actions workflow** (`.github/workflows/ci.yml`)
- Triggers on push to main branch
- Attempts to restart service with polkit (falls back to sudo)
- Ready to test once repo is pushed to GitHub

✅ **Documentation** (`README.md`)
- Complete setup instructions
- Troubleshooting guide
- Alternative approaches documented

### 2. NixOS Configuration Files (/Users/justin/configs/hetzner/)

✅ **Service configuration** (`test-app.nix`)
- Systemd service definition for test-app
- Runs as justin user on port 3001
- Service is running successfully

✅ **Polkit rules** (`polkit-rules.nix`)
- Rules created to allow justin to restart test-app without sudo
- ⚠️ **NOT WORKING** - Rules don't appear to be loaded

✅ **GitHub runner** (`github-runner-test-app.nix`)
- Separate runner configuration for test-app
- Keeps existing slipbox runner unchanged
- ⚠️ **Needs token** - Waiting for GitHub repo creation

✅ **Updated main configuration** (`configuration.nix`)
- Imports all new modules correctly
- Successfully deployed to server

## Current Issues

### 1. Polkit Rules Not Working
**Problem:** `systemctl restart test-app` still requires sudo
```bash
$ systemctl restart test-app
Failed to restart test-app.service: Access denied
```

**Investigation:**
- `/etc/polkit-1/rules.d/` directory exists but is empty
- Polkit rules from `polkit-rules.nix` are not being installed
- NixOS may require different approach for polkit rules

**Potential fixes to try:**
1. Check if polkit service is running
2. Verify polkit package is installed
3. Look for NixOS-specific polkit configuration method
4. Consider using systemd's native user service management

### 2. GitHub Runner Not Started
**Problem:** Runner needs token from GitHub
```
systemd[1]: Failed to start GitHub Actions runner.
install: cannot stat '/var/lib/github-runner-test-app-token': No such file or directory
```

**Next steps:**
1. Push repo to GitHub: `gh repo create test-app --private`
2. Get runner token from GitHub settings
3. Add token to server: `sudo bash -c 'echo TOKEN > /var/lib/github-runner-test-app-token'`

## What's Working

1. ✅ Test app service running successfully
2. ✅ Accessible on port 3001
3. ✅ Nix profile installation works
4. ✅ Manual restart with sudo works
5. ✅ NixOS configuration deploys cleanly

## Next Steps to Complete

1. **Fix polkit rules:**
   - Research NixOS polkit configuration
   - May need to use `security.polkit.enable = true`
   - Check if we need `services.polkit.enable = true`
   - Verify polkit package installation

2. **Complete GitHub setup:**
   - Create GitHub repo
   - Add runner token
   - Test CI workflow

3. **Alternative approaches if polkit fails:**
   - Try `systemd.services.test-app.restartTriggers`
   - Use systemd path units to watch profile changes
   - Consider user systemd services
   - Look into Linux capabilities (CAP_SYS_ADMIN)

## Commands for Testing

```bash
# Check if service is running
systemctl status test-app

# Test the app
curl http://135.181.179.143:3001

# Test polkit (currently fails)
systemctl restart test-app

# Test with sudo (works)
sudo systemctl restart test-app

# Check polkit rules
sudo ls -la /etc/polkit-1/rules.d/

# Check runner status
systemctl status github-runner-test-app-runner
```

## Files Created/Modified

### Test App Repository
- `/Users/justin/code/test-app/src/index.ts`
- `/Users/justin/code/test-app/package.json`
- `/Users/justin/code/test-app/flake.nix`
- `/Users/justin/code/test-app/.github/workflows/ci.yml`
- `/Users/justin/code/test-app/README.md`
- `/Users/justin/code/test-app/deploy.sh`

### NixOS Configuration
- `/Users/justin/configs/hetzner/test-app.nix`
- `/Users/justin/configs/hetzner/polkit-rules.nix`
- `/Users/justin/configs/hetzner/github-runner-test-app.nix`
- `/Users/justin/configs/hetzner/configuration.nix` (modified)

## Session 2 Learnings (September 15, 2025)

### Key Discoveries

1. **Polkit Won't Work for Our Use Case**
   - Polkit is designed for desktop environments with authentication agents
   - On headless NixOS servers, there's no polkit authentication agent running
   - The `NoNewPrivileges = true` setting conflicts with polkit's privilege escalation model
   - Even with `security.polkit.enable = true`, rules don't get applied without an agent

2. **Restart Triggers Don't Work from CI**
   - `systemd.services.<name>.restartTriggers` only work during `nixos-rebuild switch`
   - GitHub Actions can't run `nixos-rebuild switch` (requires root on the host)
   - This approach would be perfect for local deployments but not CI/CD

3. **Sudo with NOPASSWD is the Correct Solution**
   - Already working successfully for the slipbox service
   - Compatible with `NoNewPrivileges = true` because sudo runs as a separate privileged process
   - Requires adding sudo package to runner's `extraPackages`
   - Must use full systemd paths in sudo rules: `${pkgs.systemd}/bin/systemctl`

4. **GitHub Runner Package Requirements**
   ```nix
   extraPackages = with pkgs; [
     git
     curl
     sudo        # Critical: Not available by default in runner
     systemd     # For systemctl access
   ];
   ```

5. **CI Workflow Patterns**
   - Always check if sudo exists before using it: `command -v sudo &> /dev/null`
   - Provide fallback paths for systemctl: `/run/current-system/sw/bin/systemctl`
   - Use `|| true` on status checks to prevent CI failure on non-critical commands

### What Actually Works

The working solution requires:

1. **NixOS Configuration** (`github-runner-test-app.nix`):
   ```nix
   security.sudo.extraRules = [{
     users = [ "justin" ];
     commands = [
       { command = "${pkgs.systemd}/bin/systemctl restart test-app";
         options = [ "NOPASSWD" "SETENV" ]; }
     ];
   }];
   ```

2. **Runner must include sudo/systemd packages**
3. **CI workflow uses sudo**: `sudo systemctl restart test-app`

### Failed Approaches Summary

| Approach | Why It Failed | Learning |
|----------|--------------|----------|
| Polkit rules | No authentication agent on headless server | Polkit is for desktop environments |
| Restart triggers | Requires `nixos-rebuild switch` | Good for local, not for CI |
| Direct systemctl | Access denied without privileges | System services need elevated permissions |
| User systemd services | Would work but changes architecture | Viable alternative but more complex |

### Current Blockers

1. **NixOS Config Not Deployed**: The sudo rules and runner config need to be deployed to server
2. **Runner Token Missing**: GitHub runner needs registration token from repo settings
3. **Runner Not Started**: Service waiting for token file at `/var/lib/github-runner-test-app-token`

### Next Immediate Steps

1. Deploy NixOS configuration:
   ```bash
   cd ~/configs
   git add hetzner/test-app.nix hetzner/github-runner-test-app.nix
   git commit -m "Add test-app with sudo rules"
   git push && just hetzner
   ```

2. Set up runner token:
   ```bash
   gh api repos/justinmoon/test-app/actions/runners/registration-token -q .token
   ssh justin@135.181.179.143 "sudo bash -c 'echo TOKEN > /var/lib/github-runner-test-app-token'"
   ssh justin@135.181.179.143 "sudo systemctl restart github-runner-test-app-runner"
   ```

3. Merge PR and test

## Conclusion

The test app infrastructure is **90% complete**. We've identified that sudo with NOPASSWD is the correct solution for GitHub Actions on NixOS with systemd services. This matches the working slipbox configuration and is compatible with security hardening settings like `NoNewPrivileges = true`.

The polkit approach, while initially promising, is not suitable for headless CI/CD environments. The sudo approach is simpler, more reliable, and already proven in production.

## Session 3: Directory Permissions Deep Dive (September 15, 2025)

### The Real Problem Discovered

**CRITICAL FINDING**: The `/build` directory issue affects BOTH slipbox and test-app. Even slipbox with `ProtectSystem=false` and `ReadWritePaths=["/build"]` cannot write to `/build`. This entire test-app project is a minimal reproduction to solve the slipbox CI problem.

### Investigation Results

1. **Directory Permissions Look Correct**:
   - `/build` exists and is owned by root:root
   - `/build/test-app` and `/build/slipbox` owned by justin:users
   - Direct SSH as justin CAN write to these directories
   - But GitHub runners get "Read-only file system" errors

2. **Systemd Settings Comparison**:
   ```
   test-app-runner:
   - ProtectSystem=strict
   - No ReadWritePaths configured
   - StateDirectory=/var/lib/github-runner/test-app-runner
   - RuntimeDirectory=/run/github-runner/test-app-runner
   
   slipbox-runner (hetzner-runner):
   - ProtectSystem=false  
   - ReadWritePaths=["/build"]
   - STILL CANNOT WRITE TO /BUILD
   ```

3. **Mount Namespace Isolation**:
   - GitHub runners operate in a restricted mount namespace
   - This makes `/build` appear read-only regardless of:
     - File permissions
     - systemd ProtectSystem settings
     - ReadWritePaths configuration
   - This is a GitHub runner security feature, not a systemd issue

### Writable Directories for GitHub Runners

Testing confirmed runners CAN write to:
1. **StateDirectory**: `/var/lib/github-runner/<runner-name>/`
   - Persistent across reboots
   - Automatically writable with ProtectSystem=strict
   - Perfect for consistent build directory
   
2. **RuntimeDirectory**: `/run/github-runner/<runner-name>/`
   - Writable but cleared on reboot
   - Lives in tmpfs (RAM)
   
3. **Working directory**: `/run/github-runner/<runner-name>/<repo>/<repo>`
   - Changes between runs
   - Not suitable for consistent paths

### Why Nix Profile Updates Were Failing

1. **Inconsistent paths**: Each CI run used different directory
2. **Profile couldn't recognize package**: Path changes meant nix saw it as different package
3. **No actual upgrade happened**: Just installed alongside, wasting space

### The Solution: StateDirectory

Use `/var/lib/github-runner/<runner-name>/builds` for consistent builds:
- Already writable (no config changes needed)
- Persistent location
- Consistent path for nix profile
- Works within GitHub runner security model

### Failed Approaches Summary

| Approach | Why It Failed | Key Learning |
|----------|--------------|--------------|
| Write to `/build` | Mount namespace makes it read-only | GitHub runner security feature |
| `ReadWritePaths=["/build"]` | Doesn't affect mount namespace | ReadWritePaths only works within namespace |
| `ProtectSystem=false` | Still restricted by mount namespace | Runner has additional isolation |
| Restart triggers | Requires nixos-rebuild | Can't run nixos-rebuild from CI |
| Working directory builds | Path changes each run | Nix profile needs consistent paths |

### Critical Insights

1. **This is NOT a systemd problem** - It's GitHub runner mount namespace isolation
2. **StateDirectory is the way** - It's designed for exactly this use case
3. **Stop fighting the security model** - Work within the constraints
4. **Simpler than expected** - No NixOS config changes needed

### Next Steps

1. Update CI to use StateDirectory for builds
2. Test full deployment pipeline
3. Apply same solution to slipbox
4. Document solution for future projects

---
*Report generated: September 15, 2025*  
*Last updated: September 15, 2025 (Session 3)*