# AgentPort

AgentPort connects **local GGUF AI models** to **DeepSeek Harness** on Windows.

It gives you one desktop app for setting up TextGen, choosing a local model, checking GPU/RAM fit, and wiring that model into DeepSeek Harness without manually editing config files or juggling launch scripts.

## Current focus

The next build is focused on making setup much more obvious:

- clear **Installed / Missing / Needs repair** flags for TextGen and DeepSeek Harness
- one-click install buttons for TextGen and DeepSeek Harness
- automatic model discovery from common local AI tools
- clearer handling for GGUF models that need helper files like `mmproj`
- a simpler Skills page with obvious add/import buttons
- cleaner startup phase text with no broken symbols

See: [`docs/v1.6-setup-and-discovery.md`](./docs/v1.6-setup-and-discovery.md)

## What it does

- Starts and manages TextGen for local GGUF inference
- Connects the selected local model to DeepSeek Harness
- Shows GPU / RAM fit feedback before launch
- Gives clear startup progress and failure stages
- Lets you select model, context length, KV cache and offload mode
- Supports Hugging Face GGUF downloads and local GGUF imports
- Lets you offload models from VRAM
- Keeps DeepSeek Harness skills isolated in their own folder

## Download

Download the latest build from the **Releases** section.

If needed, the executable can also live in:

```text
releases/AgentPort_v1.5.0.exe
```

## Quick start

1. Download `AgentPort_v1.5.0.exe`
2. Double-click it
3. Open the setup/status area and confirm TextGen + DeepSeek Harness are installed
4. Pick or discover a GGUF model
5. Choose context length and GPU offload mode
6. Press **Apply & Start**

On a fresh PC, first launch needs internet because AgentPort has to download runtime components and any models you choose.

## Startup phases

When you press **Apply & Start**, AgentPort should walk through clean phase labels:

1. **Preflight** — checks paths, model choice and runtime state
2. **Prepare runtime** — writes TextGen and DeepSeek Harness settings
3. **Start TextGen** — starts the local model server
4. **Wait for API** — waits for TextGen on port `5100`
5. **Verify model** — confirms the selected GGUF is actually loaded
6. **Start Harness** — launches DeepSeek Harness
7. **Ready** — opens the local Harness page

If something fails, the log panel should show the exact stage and recent error output.

## Model discovery

AgentPort should search common local model locations used by tools like:

- AgentPort / TextGen
- LM Studio
- Ollama
- Unsloth Studio
- Hugging Face cache
- Jan
- GPT4All

Discovered models should be shown with their source app, file path, size, and whether any helper files were detected.

## Default ports

| Component | Port |
|---|---:|
| TextGen API | `5100` |
| DeepSeek Harness UI | `3080` |

## Files and settings

AgentPort stores persistent settings here:

```text
%USERPROFILE%\.dsh
```

DeepSeek Harness-only skills live here:

```text
%USERPROFILE%\.dsh\harness_skills
```

## Notes

- Windows only
- Models are not included
- GGUF models can be downloaded or imported through AgentPort
- Large models and runtimes can take a while to download

## Licence

MIT
