# AgentPort 4.0.0

AgentPort 4.0.0 is the first release of the rebuilt AgentPort, a minimal local
router for Codex Desktop and DeepSeek Harness. It retains opencode Go and the
other providers, and adds a managed local model path for Windows GPUs.

## What is in this release

- AgentPort naming across the router, installers, skills, control centre,
  documentation, and packaging.
- Codex Desktop integration with managed TOML configuration, provider
  publication, caller authentication, and local credential prompts.
- DeepSeek Harness support and the retained opencode Go and Zen provider
  family, including Messages and Responses variants.
- NInfer, an AgentPort-managed Windows CUDA llama.cpp runtime with release
  discovery, SHA-256 verification, staged activation, status, and explicit
  update confirmation.
- GGUF import from a Hugging Face repository or URL, or from a local .gguf
  file, with optional mmproj helper support for vision-capable models.
- Local model start, stop, and status controls, with Codex picker publication
  for imported models.
- Local page controls for the runtime card and the GGUF import flow.
- Existing Ollama, LM Studio, provider curation, harness, tray, browser panel,
  update, and rollback surfaces retained.

## Install

Download one of the release archives, verify its SHA-256, and unpack it.

Windows PowerShell:

```powershell
Expand-Archive .\AgentPort-v4.0.0-source.zip -DestinationPath .\agentport
cd .\agentport
.\install.ps1 -Target codex -Guided -WithTray
```

macOS or Linux:

```sh
tar -xzf agentport-4.0.0.tar.gz
cd agentport-4.0.0
./install.sh --target codex --guided --with-tray
```

Follow the prompts for the providers you want. Credentials are entered through
local prompts. After installation, fully quit and reopen Codex before choosing
an AgentPort model.

You can also paste the installation message from the repository README into a
Codex task and let your coding agent handle the process.

## Checksums

agentport-4.0.0.tar.gz: `7f373426ccfb9f79b5c67f64e82c79d91d0f20f4de363a3a49b568de117be8cd`

AgentPort-v4.0.0-source.zip: `b1c5b40b54a6982dd83c381b2dbed500a7b75076a2ee6ec65b46a021536fe7b5`

## Verification

The full automated test gate is green for this release: 4,224 passing tests
with no failures, covering the NInfer runtime, GGUF import, local model
lifecycle, control centre build, model switching, and the wider regression
suite. Live end to end verification on a Windows RTX 4080 is still recommended
before relying on this release for day to day work.