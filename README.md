# AgentPort

Manage several Codex accounts, connect selected API providers and run supported local GGUF models from one desktop control centre.

## Download AgentPort 3.1.23

**[Windows x64 installer](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.23/agentport-3.1.23-windows-x64.exe)**

**[Apple Silicon Mac preview](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.23/agentport-3.1.23-macos-arm64.dmg)** · [Mac ZIP alternative](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.23/agentport-3.1.23-macos-arm64.zip)

[Release notes](release-notes/v3.1.23.md) · [SHA-256 checksums](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.23/agentport-3.1.23-SHA256SUMS.txt) · [Website](https://zuravfx.github.io/AgentPort/)

## Add your Codex subscriptions

1. Open **Codex Accounts** in the left sidebar and click **Add Codex account**.
2. Finish sign-in in your browser. Repeat for each ChatGPT subscription you use.
3. Click **Choose account for a chat**, pick an account on the existing conversation in Context Manager, then click **Apply**.

You do not need a separate account-manager app or multiple Codex windows. A running task keeps its account; a pending change applies at a confirmed new turn. Existing conversation IDs and Open app/Resume controls are retained. The selected account must support the model, and live cross-account acceptance of account-scoped context remains unverified.

## Install or update

Finish active tasks and fully quit AgentPort and Codex. On Windows, run the installer over your existing copy. On Mac, open the DMG and replace AgentPort in Applications. Reopen AgentPort and Codex. The installer includes both the updated interface and matching router; no terminal build is required.

For external models, connect your provider in **API Models**, choose the models you want, and enable Codex in **Harness**. Fully quit and reopen Codex after changing its model list.

The **Mac build is an Apple Silicon preview**, ad hoc signed rather than Apple-notarised. macOS may block it; see the [Mac installation notes](release-notes/v3.1.22.md). It supports Codex and API providers; local inference is not included.

This repository distributes installers, checksums, release notes and the download page. Application source and development history are maintained privately.

[Report a compatibility issue](https://github.com/ZURAVFX/AgentPort/issues/new/choose).
