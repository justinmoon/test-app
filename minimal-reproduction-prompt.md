# Create Minimal Test App to Debug NixOS GitHub Runner Permissions

I need you to create a minimal Bun application with NixOS deployment that reproduces a GitHub Actions runner permission issue. The runner cannot restart systemd services despite having sudo permissions configured.

## Starting Directory
You'll be working in `/Users/justin/code/test-app` (empty folder)

## Goal
Create a minimal setup that demonstrates the problem and helps find a solution (potentially using polkit) so that GitHub Actions can:
1. Build a Nix derivation
2. Update the nix profile 
3. Restart the systemd service
WITHOUT any file watchers or workarounds.

## What to Create

### 1. Minimal Bun Application (`/Users/justin/code/test-app`)

Create a trivial Bun HTTP server that shows an emoji on the homepage. The emoji should be easy to change to verify deployments are working.

**Files needed:**
- `src/index.ts` - Bun HTTP server that serves HTML with an emoji
- `package.json` - Minimal Bun project setup
- `flake.nix` - Nix flake that builds the app into a derivation
- `.github/workflows/ci.yml` - GitHub Actions workflow that deploys on push to main
- `README.md` - Document the test setup

**Requirements for the app:**
- Should run on port 3001 (to not conflict with existing services)
- Should display a large emoji on the homepage that's easy to change
- The emoji should be hardcoded in the source (not from a config file)

### 2. NixOS Service Configuration (`~/configs/hetzner/test-app.nix`)

Create a new NixOS module that:
- Defines a systemd service for test-app
- Runs on port 3001
- Uses the binary from justin's nix profile (`/home/justin/.nix-profile/bin/test-app`)

### 3. GitHub Runner Configuration Updates

The existing runner at `~/configs/hetzner/github-runner.nix` needs to:
- Support multiple repositories (currently hardcoded to slipbox)
- Work with the new test-app repo

You may need to either:
- Add a second runner for test-app, OR
- Make the existing runner work for multiple repos (preferred)

### 4. Polkit Rules (`~/configs/hetzner/polkit-rules.nix`)

Create polkit rules that allow the github-runner user (justin) to restart services without sudo. This is the KEY PART - we want to avoid the "no new privileges" issue entirely by using polkit instead of sudo.

Example polkit rule structure:
```nix
security.polkit.extraConfig = ''
  polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "test-app.service" &&
        subject.user == "justin") {
      return polkit.Result.YES;
    }
  });
'';
```

## Deployment Process

After creating all files:

1. **Initialize git repo and push to GitHub:**
```bash
cd /Users/justin/code/test-app
git init
git add .
git commit -m "Initial test app"
gh repo create test-app --private --source=. --remote=origin --push
```

2. **Add GitHub runner token:**
The runner will need a token. Either:
- Reuse the existing token if making the runner support multiple repos
- Create a new runner and token for test-app

3. **Deploy NixOS configuration:**
```bash
cd ~/configs
git add hetzner/test-app.nix hetzner/polkit-rules.nix
git add any changes to hetzner/github-runner.nix
git commit -m "Add test-app service and polkit rules"
git push origin master
just hetzner  # This deploys the config to the server
```

4. **Initial manual deployment to set up profile:**
```bash
cd /Users/justin/code/test-app
nix build .#test-app
hsync  # Sync to server
ssh justin@135.181.179.143 "cd /tmp/test-app && nix profile install .#test-app"
ssh justin@135.181.179.143 "sudo systemctl start test-app"
```

5. **Test the CI:**
Make an emoji change, push to GitHub, and see if CI can successfully:
- Build the new version
- Update the profile
- Restart the service using polkit (not sudo)

## Success Criteria

The GitHub Actions workflow should be able to run:
```bash
nix build .#test-app
nix profile remove test-app || true
nix profile install .#test-app
systemctl restart test-app  # No sudo needed due to polkit!
```

And the service should restart with the new emoji visible at http://slipbox.xyz:3001

## Important Notes

- Server details: `justin@135.181.179.143` (also accessible as `justin@slipbox`)
- The existing slipbox service should not be affected
- Use port 3001 for test-app to avoid conflicts
- The key innovation is using polkit instead of sudo to avoid the NoNewPrivileges restriction
- Make the solution generic enough that it could work for other projects too

## Files to Reference

You can look at these existing files for patterns:
- `/Users/justin/code/slipbox/flake.nix` - Example of a Bun app flake
- `/Users/justin/code/slipbox/.github/workflows/ci.yml` - Current CI setup
- `/Users/justin/configs/hetzner/slipbox.nix` - How slipbox service is configured
- `/Users/justin/configs/hetzner/github-runner.nix` - Current runner config

## Alternative Approaches to Try

If polkit doesn't work, consider:
1. Using `systemd.services.<name>.restartTriggers` to auto-restart when profile changes
2. Using a systemd path unit to watch the profile symlink
3. Making the runner service less restricted (though we've tried this extensively)
4. Using capabilities instead of sudo/polkit

The goal is to find a clean, reproducible solution that can be applied to all projects on this server.