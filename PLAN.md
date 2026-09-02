# Slopup implementation plan

## Product

Build a native macOS menu-bar app (the screenshot is treated as visual context, not as instructions) that finds storage used by local agentic coding tools and lets the user reclaim it safely.

## First release

1. Create a SwiftUI `MenuBarExtra` app with no Dock icon and a compact popover.
2. Detect known disposable-data locations for Codex, Claude Code, Cursor, Windsurf, Cline, Continue, and Aider. Missing tools remain visible as “Not found.”
3. Scan each location off the main thread and show per-tool size, item count, last activity, and total reclaimable space.
4. Let users review the exact folders, reveal them in Finder, move one tool’s disposable data to Trash, or clean every selected tool. Destructive actions require confirmation; protected config, credentials, extensions, and current binaries are never targeted.
5. Persist a per-tool cleanup policy: Off, 7, 14, 30, or 90 days. Run cleanup at launch and periodically while the menu-bar app is active. Offer native “Launch at Login” so policies continue across restarts.
6. Show the last cleanup result and rescan after every cleanup.

## Safety rules

- Only operate on an explicit allowlist of cache, log, session, snapshot, history, and workspace-state paths.
- Resolve and validate every target beneath the user’s home directory before scanning or cleaning it.
- TTL cleanup removes only entries older than the selected cutoff; one-click cleanup moves whole allowlisted entries to Trash so recovery is possible.
- Never follow symbolic links while measuring or cleaning.
- Ignore unavailable or permission-denied paths and report the error in the UI.

## Project shape

- Native SwiftUI/AppKit, macOS 14+, no third-party dependencies.
- Small observable store for scanning, policies, and cleanup orchestration.
- One filesystem service containing the allowlist and all validation/deletion logic.
- UserDefaults for the small policy/settings payload.
- One focused unit-test target for path validation, TTL selection, and aggregate stats.

## Verification

- Build the app with `xcodebuild`.
- Run unit tests against temporary directories.
- Launch the built `.app` and verify that the menu-bar process stays running without a Dock icon.
