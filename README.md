# AgentPort

AgentPort makes it simple to run open local AI models with [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness) on Windows.

It detects NVIDIA hardware, manages a CUDA-accelerated GGUF backend, connects the selected model to Harness and provides guided ComfyUI and Blender MCP setup. AgentPort is the launcher and integration layer, not the AI agent itself.

## Download

**[Download AgentPort v2.0.9 for Windows](https://github.com/ZURAVFX/AgentPort/releases/download/v2.0.9/AgentPort.exe)**

The EXE is portable. Download it and double-click it. AgentPort gives visible progress while it prepares anything missing.

## The simplest setup

1. Open AgentPort.
2. Click **Download & start recommended**.
3. Wait for the model, GPU backend and Harness to become ready.
4. AgentPort opens Harness with the same model already selected.

For an NVIDIA GPU with 16 GB VRAM, the tested default is Qwen3-Coder 30B A3B at 48k context. It was verified on an RTX 4080 with filesystem, ComfyUI and Blender tools.

## What it does

- downloads and launches the recommended local agent model
- runs ordinary GGUF models through a managed CUDA llama.cpp backend
- prioritises GPU use and shows live VRAM and system RAM consumption
- discovers existing GGUF files from common local model folders
- lets you choose which discovered models appear on Home
- imports local GGUF files and optional `mmproj` vision or audio helpers
- downloads another GGUF directly from a Hugging Face repository
- starts, stops and reconnects the model backend and DeepSeek Harness
- reports live model speed and token counts when supported
- installs a faster, action-first Qwen preset to reduce unnecessary overthinking
- guides ComfyUI, Blender and general MCP configuration
- manages Harness-only skills without mixing them into other agent applications

TextGen is not required. Existing TextGen model folders may still be scanned so users can reuse GGUF files they already downloaded, but AgentPort runs those files with its own managed backend.

## Models

The Models page separates three jobs clearly:

- **Recommended:** download and start the tested 16 GB configuration.
- **Existing models:** tick **Show on Home** for models you want in the Home dropdown. **Delete** permanently removes the selected GGUF after confirmation.
- **Advanced:** import a local GGUF with an optional helper, or inspect and download a quant from Hugging Face.

NInfer remains available as an optional RTX 4080 fast-chat experiment. It requires its own converted model and cannot load arbitrary GGUF or safetensors files. On a 16 GB card it is limited to roughly 16k to 24k context, so the recommended 48k GGUF backend is the default for Harness tools and MCP workflows.

## Skills and MCPs

Open **Skills & MCPs** in AgentPort to:

- connect ComfyUI
- connect the official Blender MCP
- paste a general MCP server configuration
- install the Zura Low Thinking preset
- add a skill folder or ZIP
- create and manage Harness-only skills

No separate MCP folder or matching skill is required for an MCP connection.

## Requirements

- Windows 11
- NVIDIA RTX 30 or 40 series GPU recommended
- enough disk space for the chosen model and runtimes
- internet access for first-time downloads
- WSL Ubuntu and CUDA are only required for the optional NInfer setup

The verified release hardware is Windows 11 with an RTX 4080 16 GB. Other NVIDIA configurations use automatic GPU fitting, but are not claimed as individually verified.

## Local data

AgentPort stores its managed files under:

```text
%LOCALAPPDATA%\AgentPort
%PUBLIC%\AgentPort\models
%USERPROFILE%\.dsh
```

The app provides confirmed removal controls in Settings. Model files are never silently deleted.

## Building from source

The Windows launcher embeds the PowerShell UI and supporting runtime modules:

```powershell
go build -o AgentPort.exe main.go
```

## Historical versions

Previous releases, source history and older setup notes remain available through GitHub Releases and the repository history. They are not needed for a new installation.

## Licence

MIT
