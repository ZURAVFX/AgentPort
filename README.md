# AgentPort

AgentPort connects **local GGUF AI models** to **DeepSeek Harness** on Windows.

It gives you one simple desktop app for launching TextGen, loading a local model, checking whether it should fit your GPU, and wiring that model into DeepSeek Harness without manually editing config files or juggling launch scripts.

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
3. Pick or download a GGUF model
4. Choose context length and GPU offload mode
5. Press **Apply & Start**

On a fresh PC, first launch needs internet because AgentPort has to download runtime components and any models you choose.

## Startup phases

When you press **Apply & Start**, AgentPort walks through:

1. **Preflight** — checks paths, model choice and runtime state
2. **Prepare runtime** — writes TextGen and DeepSeek Harness settings
3. **Start TextGen** — starts the local model server
4. **Wait for API** — waits for TextGen on port `5100`
5. **Verify model** — confirms the selected GGUF is actually loaded
6. **Start Harness** — launches DeepSeek Harness
7. **Ready** — opens the local Harness page

If something fails, check the log panel inside AgentPort. It should show the exact stage and recent error output.

## GPU / RAM fit feedback

AgentPort estimates memory use from:

- model file size
- context length
- KV cache type
- selected GPU offload mode
- detected VRAM and system RAM

This is a practical launch guide, not a benchmark. It helps you avoid obviously bad model/context combinations before starting TextGen.

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
