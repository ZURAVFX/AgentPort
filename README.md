# AgentPort

Manage several Codex accounts, connect selected API providers and run supported local GGUF models from one desktop control centre.

## Download AgentPort

**[Windows x64 installer 3.1.29](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.29/agentport-3.1.29-windows-x64.exe)**

**[Apple Silicon Mac preview](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.29/agentport-3.1.29-macos-arm64.dmg)** · [Mac ZIP alternative](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.29/agentport-3.1.29-macos-arm64.zip)

[Release notes](release-notes/v3.1.29.md) · [SHA-256 checksums](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.29/agentport-3.1.29-SHA256SUMS.txt) · [Website](https://zuravfx.github.io/AgentPort/)

Windows and Apple Silicon builds are both available on 3.1.29.

## Usage and account allowances

Usage shows each saved Codex subscription separately, including its reported allowance windows and reset times. Account management and performance details expand within Usage to keep the sidebar simple.

## Haiku token safeguard

AgentPort 3.1.29 keeps connector tools behind Codex Code Mode and refuses oversized tool lists before sending a Haiku request. This prevents giant schema inventories from repeatedly consuming the context window. Native GPT context settings are unchanged.

## Subscription switching and updates

AgentPort adds **Use this subscription** in Codex Accounts and fixes a successful browser sign-in being reported as failed. Newer releases download automatically on launch, with size and checksum verification and an **Install update** button. OpenCode model discovery refreshes on every launch, preserving your choices.

## Add your Codex subscriptions

1. Open **Usage**, expand **Codex Accounts** and click **Add Codex account**.
2. Finish sign-in in your browser. Repeat for each ChatGPT subscription you use.
3. Choose **Use this subscription**. The next message uses that account, without restarting Codex. To override a particular chat, use **Choose account for a chat** and select its account in Context Manager.

You do not need a separate account-manager app or multiple Codex windows. A running task keeps its account; a pending change applies at a confirmed new turn. Existing conversation IDs and Open app/Resume controls are retained. The selected account must support the model, and live cross-account acceptance of account-scoped context remains unverified.

## Install or update

Finish active tasks and fully quit AgentPort and Codex. On Windows, run the installer over your existing copy. On Mac, open the DMG and replace AgentPort in Applications. Reopen AgentPort and Codex. The installer includes both the updated interface and matching router; no terminal build is required.

For external models, connect your provider in **API Models**, choose the models you want, and enable Codex in **Harness**. Fully quit and reopen Codex after changing its model list.

The **Mac build is an Apple Silicon preview**, ad hoc signed rather than Apple-notarised. macOS may block it; see the [Mac installation notes](release-notes/v3.1.22.md). It supports Codex and API providers; local inference is not included.

This repository distributes installers, checksums, release notes and the download page. Application source and development history are maintained privately.

[Report a compatibility issue](https://github.com/ZURAVFX/AgentPort/issues/new/choose).
