# AgentPort v3.0.2

Fixes the missing-dependency and control-protocol errors in the Windows installer.

## Fixes

- The router now includes its locked production JavaScript dependencies. Provider and Harness reads work before the first setup run.
- The installer includes the matching control protocol manifest, so setup recognises the bundled router.
- App-managed router files update with the desktop app, including installations created by 3.0.1. Existing Python environments, local models and installation state are preserved.
- Packaged desktop helpers include their dependencies, and Windows tray commands include their required launcher scripts.
- Release verification exercises clean and 3.0.1 upgrade profiles outside the development checkout.

## Install or update

Close AgentPort, run `AgentPort-Setup-3.0.2.exe`, then reopen AgentPort. If the router was already running, restart it from the app so its running process loads the updated files. There is no need to uninstall or remove your settings.

Explicit source overrides and Git-managed router checkouts remain operator-managed; update those to the matching version separately.

The Windows installer is unsigned. The release includes `SHA256SUMS` to verify the download.
