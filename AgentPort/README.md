# AgentPort

AgentPort is a simple Windows desktop app for running local GGUF models and connecting them into agent-style workflows.

It manages the boring bits around local model setup: TextGen, model folders, context length, GPU offload, memory fit checks, startup progress, logs, and a separate Harness skills folder.

![AgentPort UI preview](./assets/ui-preview.svg)

## Download

Latest build: **AgentPort v1.5.0**

> The EXE is not committed yet because this GitHub connector cannot upload local binary release assets directly. Upload `AgentPort_v1.5.0.exe` to `AgentPort/releases/` or create a GitHub Release and attach it there.

## What it does

- Runs local GGUF models through TextGen
- Connects the selected model into DeepSeek Harness-style workflows
- Shows whether the selected model/context should fit your GPU
- Gives clear startup phases and progress feedback
- Lets you change model, context, GPU offload and KV cache from one screen
- Keeps Harness skills isolated in their own folder
- Supports Hugging Face GGUF downloads and local GGUF imports
- Lets you offload models from VRAM without juggling launch scripts

## Quick start

1. Download `AgentPort_v1.5.0.exe`.
2. Double-click it.
3. Pick or download a GGUF model.
4. Choose context length and GPU offload.
5. Press **Apply & Start**.

On a fresh PC, AgentPort needs internet access while it downloads local runtime components and any models you choose.

## Startup phases

When you press **Apply & Start**, AgentPort walks through:

1. **Preflight** — checks paths, selected model and runtime state.
2. **Prepare runtime** — writes TextGen and Harness settings.
3. **Start TextGen** — starts the local model server.
4. **Wait for API** — waits for TextGen on port `5100`.
5. **Verify model** — confirms the selected GGUF is actually loaded.
6. **Start Harness** — launches the agent UI.
7. **Ready** — opens the local Harness page.

If something fails, check the log panel inside AgentPort first. It should show the exact stage and recent error output.

## GPU / RAM fit feedback

AgentPort estimates memory use from the model file size, context length, KV cache type, GPU offload mode, detected VRAM and system RAM.

The fit meter is a guide, not a benchmark. It helps you avoid obvious bad combinations before launching.

## Default ports

| Component | Port |
|---|---:|
| TextGen API | `5100` |
| Harness UI | `3080` |

## Where files live

AgentPort uses:

```text
%USERPROFILE%\.dsh
```

Harness-only skills live here:

```text
%USERPROFILE%\.dsh\harness_skills
```

## Branding

![AgentPort icon](./assets/icon.svg)

## Licence

MIT.
