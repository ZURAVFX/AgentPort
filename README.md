# AgentPort

AgentPort puts other models inside the Codex desktop app. It keeps your GPT
models where they are and adds the ones you bring in the same chat: opencode Go,
DeepSeek, Kimi, Grok, GLM and whatever else you enable. Local GGUF models run on
your own Windows GPU through a managed llama.cpp runtime, with an optional
mmproj helper file for vision models.

Provider credentials stay on your computer.

## Install

1. Download `AgentPort-Setup-3.0.1.exe` from the [latest release](https://github.com/ZURAVFX/AgentPort/releases/latest).
2. Run it. It installs for the current user, so Windows does not ask for
   administrator rights, and it leaves an **AgentPort** shortcut on your
   desktop.
3. Open AgentPort and use the Codex page to configure Codex Desktop. Restart
   Codex when it asks.

The installer carries Node, uv and a router checkout, so you do not have to
install anything first.

If you already run the router AgentPort was forked from, AgentPort recognises
its configuration blocks and takes them over, keeping the provider keys you
already entered.

## Let your agent do it

Paste this into a Codex task:

```text
Install AgentPort on this machine. Download AgentPort-Setup-3.0.1.exe from
https://github.com/ZURAVFX/AgentPort/releases/latest, verify it against the
SHA256SUMS published on that release, and run it. Then open AgentPort and set
up the Codex target with the providers I choose. Preserve my existing Codex
models, profiles, settings and ChatGPT login, run the AgentPort doctor, and
leave the final Codex restart to me. Never ask me to paste a token or API key
into chat.
```

## What is new in 3.0.1

- One-click Windows installer with a desktop shortcut and no admin prompt.
- Codex Desktop is the main target. If an earlier installation of the router
  this project was forked from is present, it is taken over rather than
  refused, so Codex can always be configured.
- Local models: start a managed Windows CUDA llama.cpp runtime, or import a
  GGUF from a Hugging Face repository, a URL, or a file on disk, with an
  optional vision projector helper.
- opencode Go is available as a provider.
- Large tool results are shaped before they reach a routed model, so a long
  build log does not eat your context window.
- The previous all-or-nothing test gate was replaced with a runner that
  isolates each test file, so a single failure cannot hide the state of the
  rest.

## Verifying the download

```powershell
certutil -hashfile AgentPort-Setup-3.0.1.exe SHA256
```

Compare the result with the value in `SHA256SUMS` on the release page.

## Security

Windows may show a SmartScreen warning on first run because the installer is not
code signed. Choose **More info**, then **Run anyway** if you are happy to
proceed.
