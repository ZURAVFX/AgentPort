# AgentPort

AgentPort connects Codex to selected API providers and local GGUF models through one desktop control centre.

**Download:** [AgentPort 3.1.20 for Windows](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.20/agentport-3.1.20-windows-x64.exe)
**Mac preview:** [AgentPort 3.1.21 for Apple Silicon](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.21/agentport-3.1.21-macos-arm64.dmg), including M5. Codex and API models only; local inference is not included.
**Website:** [zuravfx.github.io/AgentPort](https://zuravfx.github.io/AgentPort/)

Run the per-user installer, open AgentPort, then connect Codex and choose the models you want. Restart Codex after changing the published model list so its picker refreshes.

This repository distributes release builds and release notes. Application source is maintained privately.

On Mac, drag AgentPort into Applications, connect your provider in API Models,
then enable Codex in Harness. The first connection prepares the Python gateway
automatically. Fully quit and reopen Codex afterwards. This preview is ad-hoc
signed, rather than Apple-notarised; if macOS blocks it, follow the
[Mac installation notes](release-notes/v3.1.21.md).

See the [3.1.20 release notes](release-notes/v3.1.20.md) or [report a compatibility issue](https://github.com/ZURAVFX/AgentPort/issues/new/choose).
