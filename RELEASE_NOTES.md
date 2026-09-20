# AgentPort 4.0.2

AgentPort 4.0.2 makes an existing installation of the router this project was
forked from migratable. That installation writes the same three Codex blocks
under its own marker names and keeps its merged model catalog in
`<CODEX_HOME>/codex-router`. Those blocks and that catalog read as user-owned,
so every managed write refused and Codex could not be configured at all.

If you hit "the existing Codex TOML configuration cannot be safely edited" or a
refusal naming a catalog path, this is the release that fixes it.

## What changed

- The predecessor's three Codex blocks can now be taken over. A takeover
  removes them exactly as it removes this project's own older layouts, then
  writes AgentPort's blocks in their place. Content outside those blocks is
  preserved untouched.
- The guard is unchanged. A catalog outside every managed marker block is still
  refused, and a taken-over configuration disables back to your own content
  with no managed keys left behind.
- That installation is now a recognized migration target. Detection previously
  reported its catalog as somebody else's router, which left no way forward. It
  is reported by name, so guided setup offers the snapshot-and-migrate step and
  the doctor names `./bin/doctor --fix --migrate-known`.
- Escaped Windows catalog paths now detect. Detection compared raw config text
  against a native path, but a predecessor writes its path as a TOML basic
  string, so on Windows every separator arrives escaped and the installation
  went unnoticed.
- Provider credentials in `<CODEX_HOME>/codex-router` are adopted. Its
  credential filenames are the same ones this tree uses, so an existing key,
  including an opencode Go key, is found without being entered again.

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
- Existing Ollama, LM Studio, provider curation, harness, tray, browser panel,
  update, and rollback surfaces retained.

## Install

Download one of the release archives, verify its SHA-256, and unpack it.

Windows PowerShell:

```powershell
Expand-Archive .\AgentPort-v4.0.2-source.zip -DestinationPath .\agentport
cd .\agentport
.\install.ps1 -Target codex -Guided -WithTray
```

macOS or Linux:

```sh
tar -xzf agentport-4.0.2.tar.gz
cd agentport-4.0.2
./install.sh --target codex --guided --with-tray
```

Guided setup detects a recognized earlier installation and asks before
snapshotting and migrating it. For a non-interactive run, pass
`--migrate-known`. Follow the prompts for the providers you want. Credentials
are entered through local prompts. After installation, fully quit and reopen
Codex before choosing an AgentPort model.

## Checksums

agentport-4.0.2.tar.gz (15,088,603 bytes):
`d75743a1ebf3df5663cfe96374e90c5db7b468afe7987d1aaa47101413a27960`

AgentPort-v4.0.2-source.zip (15,765,447 bytes):
`7d39e7821aa1fd012a2ebcbe253a3f937fa7dcec1d5ab0b355dbdf59528ab334`

## Verification

Four regression tests were added: a takeover that preserves operator content, a
disable that returns to it, a guard proving only the markers authorize a
replacement, and a detection test for the predecessor installation. The full
automated test gate is green: 4,361 tests, 4,228 passing with no failures and
133 skipped. The takeover was also exercised against a copy of a real Codex
configuration carrying all three predecessor blocks, including its escaped
Windows catalog path.

Live end to end verification on a Windows RTX 4080 is still recommended before
relying on this release for day to day work.
