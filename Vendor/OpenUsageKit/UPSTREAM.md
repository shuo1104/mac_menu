# OpenUsageKit upstream provenance

This directory is a **vendored, pruned** copy of OpenUsage used by MM
as a local Swift package (`XCLocalSwiftPackageReference`).

| Field | Value |
|---|---|
| Upstream project | OpenUsage (Robin Ebers) |
| License | MIT — see `LICENSE` |
| Copyright | Copyright (c) 2026 Robin Ebers |
| Integration mode | Local SPM library target `OpenUsageKit` |
| Package tools | `// swift-tools-version: 6.1` |
| Platform | macOS 14+ |

## What is compiled

`Package.swift` builds only `Sources/OpenUsage` and **excludes**:

- `App/`
- `Views/`
- `Services/Telemetry.swift`
- `Stores/TelemetryRecorder.swift`
- `Support/AppNotifications.swift`
- `Support/AppShortcuts.swift`
- `Support/PopoverDismissReader.swift`
- `Support/ShareCardRenderer.swift`
- `Support/TooMuchTransparencyKeyReader.swift`

MM talks to the package only through the public facade in
`Sources/OpenUsage/OpenUsageEmbeddedService.swift`
(`EmbeddedOpenUsageService` and related types).

## Why no sandbox

Provider collectors read local AI-CLI credential stores and usage logs under
the user home directory (`~/.claude`, `~/.codex`, Cursor state DB, etc.). That
requires the host app to run **without** App Sandbox. Credentials stay in their
original files / Keychain; MM does not re-store them.

## Syncing upstream

1. Record the upstream git URL and commit SHA here when you next refresh.
2. Re-apply the `Package.swift` exclude list and keep
   `OpenUsageEmbeddedService.swift` as the only app-facing surface.
3. Rebuild and run `python3 -m unittest discover -s tests`.

Upstream URL / commit: _(not recorded — fill in on next vendor refresh)_
