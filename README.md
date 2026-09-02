# Slopup

A native macOS menu-bar app for finding and cleaning session data left by agentic coding tools.

## Run

```sh
./Scripts/build-app.sh
open build/Slopup.app
```

For a normal local install, build a release and drag `build/Slopup.app` into your Applications folder.

## Install from GitHub

Each `v*` tag publishes a universal GitHub Release:

```sh
curl -fsSL https://github.com/snowdamiz/slopup/releases/latest/download/install.sh | zsh
```

Run the same command again to update. It verifies the release checksum and installs into `~/Applications`; set `SLOPUP_INSTALL_DIR` to choose another location.

Pushes and pull requests run tests and a release build. Publish a user-facing version with:

```sh
git tag v0.1.0
git push origin main v0.1.0
```

Slopup supports Codex, Claude Code, Cursor, Windsurf, Cline, Continue, and Aider. Expand any tool to review the exact allowlisted folders. Manual cleanup moves data to Trash; opt-in retention policies permanently delete expired data once an hour while Slopup runs.

## Test

```sh
swift test
```
