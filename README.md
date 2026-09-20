# AgentPort

AgentPort is a minimal local router for Codex Desktop and DeepSeek Harness. It
keeps your GPT models in Codex while adding your own providers in the same
chat: opencode Go, DeepSeek, Kimi, Grok, GLM, and the other providers you
choose. Local GGUF models run on your own Windows GPU through the managed
NInfer llama.cpp runtime, with optional mmproj helper files for vision models.

All provider credentials stay on your computer.

## Install

The latest release contains the source archives and their SHA-256 checksums:

- `agentport-4.0.2.tar.gz` and `AgentPort-v4.0.2-source.zip`
- `agentport-4.0.2.tar.gz.sha256` and `AgentPort-v4.0.2-source.zip.sha256`

Download an archive, verify its checksum, and unpack it. Then run the installer
from that folder.

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

The installer asks which providers you want. Credentials are entered through
local prompts, never through chat. When it finishes, fully quit and reopen
Codex and start a new task to choose a routed model.

If you already run the router AgentPort was forked from, guided setup detects
it and asks before snapshotting and migrating it. Your provider keys are picked
up from its state directory, so you do not have to enter them again. For a
non-interactive run, pass `--migrate-known`.

## Let your agent install it

Paste this into a Codex task:

```text
Install AgentPort on this machine from the latest release archive at
https://github.com/ZURAVFX/AgentPort/releases. Download
agentport-4.0.2.tar.gz, verify its SHA-256, unpack it, and follow AGENTS.md.
Set up the Codex target with the providers I choose. If an earlier AgentPort or
the router it was forked from is already installed, migrate it with
--migrate-known rather than editing my configuration by hand. Preserve my
existing Codex models, profiles, settings, and ChatGPT login. Use only the
provider authentication I choose, run the AgentPort doctor, and leave the final
app restart to me. Never ask me to paste a token or API key into chat.
```

## What is new in 4.0

- NInfer, a managed Windows CUDA llama.cpp runtime with checksum-verified
  updates and explicit install confirmation.
- GGUF import from a Hugging Face repository or URL, or from a local .gguf
  file, with optional mmproj helper support.
- Start, stop, and status controls for local models, with Codex picker
  publication so a local model appears alongside your cloud models.
- A Local page flow for runtime status, updates, and GGUF imports with model
  selection.
- Codex Desktop and DeepSeek Harness as the primary targets, with the broader
  provider and harness surface retained.

## What is new in 4.0.1

- Naming cleanup. Every product-facing trace of the upstream project name is
  gone from the interface, the messages, and the documentation.
- The stale pre-rebuild Homebrew formula is removed.

## What is new in 4.0.2

- An existing installation of the router AgentPort was forked from can now be
  taken over. Previously its managed blocks and merged catalog read as
  user-owned, so every managed write refused and Codex could not be configured
  at all.
- That installation is now reported by name during setup and by the doctor, so
  the snapshot-and-migrate step is offered instead of a dead end.
- Provider credentials stored in its state directory are adopted, including an
  existing opencode Go key.

## Security

Windows may show a SmartScreen warning for the first run because the binaries
are not code signed. Verify the SHA-256 of any downloaded archive before
unpacking it and compare the checksum against the one published in the release
notes.
