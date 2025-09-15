# Implementation Report: NixOS GitHub Runner Permissions Test App

**Date:** September 15, 2025  
**Status:** Partially Complete - Polkit rules not working yet

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

## Conclusion

The test app infrastructure is **80% complete**. The main blocker is that polkit rules aren't being applied correctly in NixOS. This is the critical piece for solving the "NoNewPrivileges" issue with GitHub runners.

The fallback plan is to use one of the alternative approaches (systemd restart triggers, path units, or user services) if polkit cannot be made to work.

---
*Report generated: September 15, 2025*