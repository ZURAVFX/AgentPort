# AgentPort v3.0.3

Fixes setup failing with `Cannot find module ...npm-prefix.js` in the Windows installer.

- Includes the complete bundled npm distribution, including its internal dependencies.
- Repairs the incomplete Node/npm installation left by 3.0.1 or 3.0.2 automatically when the app next uses the runtime.
- Leaves identical runtime executables in place, so the missing npm files can be restored without overwriting a running Node executable.
- Checks the packaged npm launcher and performs an offline dependency install in both fresh and upgrade test profiles.

Close AgentPort, run `AgentPort-Setup-3.0.3.exe`, then reopen it and retry setup. No uninstall or manual deletion is needed.

This release also includes the provider-loading, protocol-manifest and router-upgrade fixes from 3.0.2. The Windows installer remains unsigned; `SHA256SUMS` is included to verify the download.
