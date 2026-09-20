# AgentPort 4.0.1

AgentPort 4.0.1 is a naming and packaging cleanup on top of the v4 rebuild.
There are no behavioural changes to routing, providers, or local model
handling.

## What changed

- Every product-facing trace of the upstream project name is gone. The Control
  Centre service label, the Managed Codex and caller-key error messages, the
  Gemini and Claude transport refusals, the install summary, the Hermes publish
  hint, the Homebrew readiness check, and the GitHub issue templates now read
  AgentPort.
- Documentation copy repaired. Several strings still described AgentPort as
  "a local agentport" after the v4 rename sweep, and the docs landing page
  header and footer still read CODEX ROUTER. Both now read correctly.
- Stale pre-rebuild Homebrew formula removed. `packaging/homebrew/agentport.rb`
  still pointed at v0.4.0-beta.2 and carried a "NOT YET INSTALLABLE" header.
  `Formula/agentport.rb` is the only formula the release workflow generates, so
  the dead duplicate is gone.
- Version bumped to 4.0.1 across `package.json`, the Control Centre package,
  and both lockfiles.

The upstream MIT attribution in `LICENSE` and `NOTICE.md` is unchanged. The
licence requires that notice to be kept.

## What is in the 4.0 rebuild

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
Expand-Archive .\AgentPort-v4.0.1-source.zip -DestinationPath .\agentport
cd .\agentport
.\install.ps1 -Target codex -Guided -WithTray
```

macOS or Linux:

```sh
tar -xzf agentport-4.0.1.tar.gz
cd agentport-4.0.1
./install.sh --target codex --guided --with-tray
```

Follow the prompts for the providers you want. Credentials are entered through
local prompts. After installation, fully quit and reopen Codex before choosing
an AgentPort model.

You can also paste the installation message from the repository README into a
Codex task and let your coding agent handle the process.

## Checksums

agentport-4.0.1.tar.gz (15,084,552 bytes):
`0b5f7240b82217549dcaa370485f125924c999cfc5dae427260b6d9705400108`

AgentPort-v4.0.1-source.zip (15,761,014 bytes):
`c195ae4414e825a061b0a607ba4ceeeade947936555a1c86f1e7505c8c6e7a3c`

## Verification

The full automated test gate is green for this release: 4,357 tests, 4,224
passing with no failures and 133 skipped, covering the router, providers,
harness clients, NInfer runtime, GGUF import, local model lifecycle, Control
Centre build, model switching, and the wider regression suite. Live end to end
verification on a Windows RTX 4080 is still recommended before relying on this
release for day to day work.
