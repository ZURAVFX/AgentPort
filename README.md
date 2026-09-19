# AgentPort

AgentPort connects local and external AI models to Codex Desktop and DeepSeek
Harness on Windows. It keeps Codex's built-in GPT models and account login
native while adding AgentPort models to the same model picker.

## Install

1. [Download AgentPort.exe from the latest release](https://github.com/ZURAVFX/AgentPort/releases/latest).
2. Download `AgentPort.exe.sha256` from the same release if you want to verify
   the file manually.
3. Double-click `AgentPort.exe`.

AgentPort is portable. There is no source checkout, package manager or manual
configuration to install.

### Ask your coding agent to install it

Copy and send this message to your coding agent:

> Download the latest AgentPort.exe and AgentPort.exe.sha256 from
> https://github.com/ZURAVFX/AgentPort/releases/latest, verify the SHA-256,
> save the verified executable in a new AgentPort folder under my Downloads
> folder, run it once, and tell me when the AgentPort control centre opens.
> Do not disable or bypass Windows security protections.

## Main integrations

- Codex Desktop, including its existing built-in GPT models
- DeepSeek Harness
- Managed CUDA llama.cpp for local GGUF models
- Optional nInfer runtime for compatible RTX 4080 workflows
- ComfyUI and Blender MCP setup

The supported integrations in this release are Codex Desktop and DeepSeek
Harness. Other integrations are not advertised until they are ready.

## Local runtime updates

AgentPort checks official llama.cpp Windows CUDA releases in the background.
When a newer verified build is available, AgentPort offers an update. It never
installs the runtime update without confirmation and does not interrupt a model
that is already running.

## Windows security

Each release includes a SHA-256 checksum. A matching checksum verifies the
downloaded bytes, but it does not replace normal Windows security checks. Do
not disable Microsoft Defender or add an exclusion to run a blocked build.

## Licence

AgentPort is released under the MIT Licence.
