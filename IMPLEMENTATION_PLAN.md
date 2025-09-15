# Implementation Plan: NixOS Polkit-Based Service Restart for test-app

This plan completes the minimal reproduction by enabling polkit-based service restarts from a self‑hosted GitHub runner, validates end‑to‑end CI, and documents fallbacks. It does not require editing application code.

## Objectives
- Allow `justin` (runner user) to `systemctl restart test-app` without sudo via polkit.
- Verify CI builds, installs to profile, and restarts service using polkit.
- Keep slipbox unaffected; keep approach reusable.

## Prerequisites
- Access to `~/configs` flake and Hetzner host deployment command (`just hetzner` or `nixos-rebuild` flow).
- GitHub repo `test-app` and a registration token for the self‑hosted runner.
- Ability to SSH to server as `justin`.

## Phase 1 — Enable and Validate Polkit

1) Enable polkit (temporary debug on):
- In `~/configs/hetzner/configuration.nix` add:
  - `security.polkit.enable = true;`
  - `security.polkit.debug = true;` (remove later)

2) Consolidate polkit rules:
- Prefer a single rules source: keep `~/configs/hetzner/polkit-rules.nix` as the one place.
- Remove the duplicate `security.polkit.extraConfig` block from `slipbox.nix` after confirming `polkit-rules.nix` covers slipbox.
- Ensure rules allow `justin` to manage only the intended units and verbs:
  - `action.id == "org.freedesktop.systemd1.manage-units"`
  - `action.lookup("unit") in {"test-app.service", "slipbox.service"}`
  - `action.lookup("verb") in {"restart", "start", "stop"}`
  - `subject.user == "justin"`
- Optional: add a `polkit.log(...)` line while debug is on for easier tracing.

3) Deploy and verify on server:
- Deploy NixOS configuration (e.g., `just hetzner`).
- Check service and rules presence:
  - `sudo systemctl status polkit --no-pager`
  - `sudo ls -la /etc/polkit-1/rules.d/` (should show a generated rules file)
- Validate rule with and without interaction:
  - `pkcheck --action-id org.freedesktop.systemd1.manage-units --process $$ --allow-user-interaction=no --detail unit test-app.service --detail verb restart; echo $?` → `0`
- Test restart as `justin` (no sudo):
  - `systemctl restart test-app`
  - `journalctl -u polkit -n 100 --no-pager` (should show rule evaluation granted)

Expected outcome: `systemctl restart test-app` succeeds without sudo under user `justin`.

## Phase 2 — Runner Setup for test-app

1) Create GitHub repo and push if not already:
- In `/Users/justin/code/test-app`:
  - `git init && git add -A && git commit -m "init"`
  - `gh repo create test-app --private --source=. --remote=origin --push`

2) Provision test-app runner token on server:
- `sudo install -m 600 /dev/stdin /var/lib/github-runner-test-app-token <<< "$TOKEN"`
- Start/verify runner:
  - `systemctl status github-runner-test-app-runner --no-pager`

3) Labels and user:
- `github-runner-test-app.nix` uses `user = "justin"` and label `self-hosted`. Ensure your workflow uses appropriate labels or default self‑hosted.

## Phase 3 — End‑to‑End CI Test

1) Trigger CI with a visible change:
- Change emoji in `src/index.ts`, commit, push to `main`.

2) Observe runner:
- `journalctl -u github-runner-test-app-runner -f` during the run.

3) Validate CI steps on server:
- Confirm profile updated: `nix profile list | grep test-app`
- Confirm restart performed without sudo path in logs.
- Verify app: `curl -s http://slipbox.xyz:3001 | head -n 5`

Expected outcome: CI runs `systemctl restart test-app` without sudo and site shows new emoji.

## Phase 4 — Hardening and Cleanup

- Remove debug logging after validation:
  - `security.polkit.debug = false;`
- Keep a single `security.polkit.extraConfig` definition in `polkit-rules.nix`.
- Restrict rules to exactly the units/verbs needed (already covered above).
- Remove CI sudo fallback for restart once confident (kept initially for safety):
  - Keep build+profile install; drop `sudo systemctl restart ...` branch.
- Update `~/configs/hetzner/README.md` if it still references `github-runner` user for this host; you are running runners as `justin` now.

## Phase 5 — Fallbacks if Polkit Fails

If polkit cannot be made to work in your environment, choose one:

- Systemd path unit watching profile:
  - Create a `test-app-profile.path` with `PathChanged=/home/justin/.nix-profile/bin/test-app` and `Unit=test-app.service` to auto-restart on updates.

- `restartTriggers`:
  - Reference a store path that changes with each build in the unit; systemd will restart when it changes.

- User service:
  - Run `test-app` as a user service (`systemctl --user`), enable lingering (`loginctl enable-linger justin`), and let CI restart it as the same user without system-level polkit.

## Verification Checklist

- Polkit enabled and rules installed:
  - [ ] `systemctl status polkit` is active
  - [ ] `/etc/polkit-1/rules.d/*.rules` exists
  - [ ] `pkcheck` for `manage-units` + `unit=test-app.service` + `verb=restart` returns 0

- Restart without sudo works:
  - [ ] `systemctl restart test-app` as `justin` succeeds
  - [ ] `journalctl -u test-app -n 50` shows restart

- Runner operational:
  - [ ] `systemctl status github-runner-test-app-runner` active
  - [ ] Token file present with 600 perms

- CI success:
  - [ ] Build/install to profile completed
  - [ ] Restart via polkit path (not sudo) executed
  - [ ] Endpoint shows updated emoji

## Troubleshooting Quick Hits

- Unit/verb mismatch:
  - Inspect polkit logs (`journalctl -u polkit`) to see `action.id`, `unit`, `verb`, `subject.user`; adjust rule accordingly.
- D‑Bus access:
  - Ensure the runner service has access to `/run/dbus/system_bus_socket` (avoid over‑hardening). Default module settings are fine.
- Subject user mismatch:
  - Your rules allow `subject.user == "justin"`; ensure runner is configured with `user = "justin"`.
- Polkit not enabled:
  - Without `security.polkit.enable = true`, extraConfig won’t load.

## Success Criteria
- `systemctl restart test-app` succeeds as `justin` without sudo, both interactively and in CI.
- CI builds, installs, restarts, and the site updates on port 3001.

## Time & Ownership
- Phase 1: 15–30 min (deploy + verify)
- Phase 2: 10–15 min (runner token + start)
- Phase 3: 10–20 min (CI run + validate)
- Phase 4: 10 min (cleanup)

Owner: justin

## Command Snippets

- Check polkit grant decision:
  - `pkcheck --action-id org.freedesktop.systemd1.manage-units --process $$ --allow-user-interaction=no --detail unit test-app.service --detail verb restart; echo $?`
- Restart and review logs:
  - `systemctl restart test-app && journalctl -u test-app -n 50 --no-pager`
- Runner status:
  - `systemctl status github-runner-test-app-runner --no-pager`

---
This plan intentionally focuses on NixOS configuration and CI integration, leaving the application code unchanged.
