# AgentPort

Manage several Codex accounts, connect selected API providers and run supported local models from one desktop control centre.

## Download AgentPort

**[Windows x64 installer 3.1.42](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.42/agentport-3.1.42-windows-x64.exe)**

**[Apple Silicon Mac preview 3.1.42](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.42/agentport-3.1.42-macos-arm64.dmg)** · [Mac ZIP alternative](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.42/agentport-3.1.42-macos-arm64.zip)

[Release notes](release-notes/v3.1.42.md) · [SHA-256 checksums](https://github.com/ZURAVFX/AgentPort/releases/download/v3.1.42/agentport-3.1.42-SHA256SUMS.txt) · [Website](https://zuravfx.github.io/AgentPort/)

Windows and Apple Silicon downloads both contain AgentPort 3.1.42.

## Clearer local controls and interface

3.1.42 fixes the cramped Dashboard speed table and page overflow. Model names and every speed metric stay visible at desktop and narrow window sizes. It also includes the shared light and dark visual design, larger controls, clearer states and simpler model rows. Local includes the tested native NInfer GSQ3 profile and Flash Next with Strata, with explicit Start and Stop & unload controls. Existing native GSQ3 files in WSL are reused; a fresh system still needs the native runtime and model installed as shown in Setup. No real model was reloaded during this interface audit.

## GPT context windows

In **Context Manager → GPT context windows**, configure each native GPT model independently. Choose Codex default, a 1M preset with compaction at 900K, or custom limits within the supported maximum. Save, fully quit and reopen Codex, then start a new chat. Larger budgets can increase latency and usage. Local and third-party models retain their own settings.

Account sign-in now keeps device codes visible, with copy, retry and cancel controls. NVIDIA NIM request compatibility fixes are included.

## Optional routing settings

**Alternative Codex routing (advanced)** is a compatibility mode, not the main AgentPort switch. Standard routing can work with it off. Leave it unchanged when models are working. **Allow ChatGPT in other local apps** is only needed to let other local clients spend your ChatGPT allowance; Codex itself and saved-account switching do not need it.

## Global routing and startup

The top of Context Manager now holds **Global Codex routing account**. It selects the subscription for chats following the global default; per-chat choices stay in place. Settings and Usage link to this one set of account controls.

**Settings → Background service → Run at startup** opens AgentPort when you sign in to your computer. This manages the app login entry separately from the router service start policy. It stays unchanged until you choose a setting.

## Steering and updates

3.1.42 fixes AgentPort rejecting Codex interruption messages while steering a running reply. Install update now queues the verified installer while model requests, downloads or sign-in are active, with a clear waiting message and Cancel update. It opens when the router is confirmed idle. Finish active chats before installation, then reopen AgentPort and Codex to load the updated router. On Mac, finish the usual Applications replacement after the DMG opens. Windows and Apple Silicon packages share the same tested source.

Older versions retain their old busy-update behaviour until updated once. Finish active requests before that first installation. Queue state lasts for the current AgentPort session.

## Find your models

Routed model names in Codex start with their provider, for example `(OpenRouter) Qwen`. API Models groups providers alphabetically, with free models first and model names A–Z. Certified subagent routes retain their priority slots in Codex. NVIDIA NIM setup is under **API Models → Connect provider → NVIDIA NIM**.

## Usage and account allowances

Usage shows each saved Codex subscription separately, including its reported allowance windows and reset times. Account management is at the top of Context Manager. Usage retains allowance readings and performance details.

## Claude Haiku removed

Claude Haiku is removed from the catalogue. Stale Haiku requests are blocked locally before forwarding. Its usage behaviour was not reliable enough to keep available. Native GPT context settings stay at their defaults unless you save a per-model override.

## Subscription switching and updates

Choose **Use this subscription** at the top of Context Manager. Browser sign-in keeps each saved account separate and reports whether login completed. Newer releases download automatically on launch, with size and checksum verification and an **Install update** button. OpenCode model discovery refreshes on every launch, preserving your choices.

## Add your Codex subscriptions

1. Open **Context Manager** and click **Add Codex account** in the top card.
2. Finish sign-in in your browser. Repeat for each ChatGPT subscription you use.
3. Choose **Use this subscription**. The next message uses that account, without restarting Codex. To override a particular chat, select its account in the session list below and press Apply.

You do not need a separate account-manager app or multiple Codex windows. A running task keeps its account; a pending change applies at a confirmed new turn. Existing conversation IDs and Open app/Resume controls are retained. The selected account must support the model, and live cross-account acceptance of account-scoped context remains unverified.

## Install or update

Finish active tasks and fully quit AgentPort and Codex. On Windows, run the installer over your existing copy. On Mac, open the DMG and replace AgentPort in Applications. Reopen AgentPort and Codex. The installer includes both the updated interface and matching router; no terminal build is required.

For external models, connect your provider in **API Models**, choose the models you want, and enable Codex in **Harness**. Fully quit and reopen Codex after changing its model list.

The **Mac build is an Apple Silicon preview**, ad hoc signed rather than Apple-notarised. macOS may block it; see the [Mac installation notes](release-notes/v3.1.22.md). It supports Codex and API providers; local inference is not included.

This repository distributes installers, checksums, release notes and the download page. Application source and development history are maintained privately.

[Report a compatibility issue](https://github.com/ZURAVFX/AgentPort/issues/new/choose).
