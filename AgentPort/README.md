# AgentPort

AgentPort is a free Windows app for connecting **local GGUF AI models** to **DeepSeek Harness**.

It is currently built around this setup:

```text
GGUF model → TextGen local API → DeepSeek Harness
```

The aim is simple: choose a local model, check whether it should fit your GPU, start TextGen, verify the model loaded, then launch DeepSeek Harness with the matching config.

## Download

Download the latest build from this repo:

```text
AgentPort/releases/AgentPort_v1.5.0.exe
```

If the EXE is not visible yet, download it from the release/assets area once uploaded.

## What AgentPort does

- Connects local GGUF models to DeepSeek Harness
- Starts TextGen with the selected model and context size
- Writes the matching DeepSeek Harness model config
- Shows GPU VRAM and system RAM fit feedback before launch
- Gives clear staged startup progress
- Verifies that TextGen actually loaded the selected model
- Opens DeepSeek Harness when the stack is ready
- Keeps Harness-only skills separate from other project skills
- Lets you import local GGUF files or download GGUFs from Hugging Face
- Lets you offload the model from VRAM when you are done

## Quick start

1. Download `AgentPort_v1.5.0.exe`.
2. Double-click it.
3. Choose or install a GGUF model.
4. Pick context length, KV cache and GPU offload mode.
5. Press **Apply & Start**.
6. Wait for the staged startup checks to complete.
7. Use the model inside DeepSeek Harness.

On a fresh PC, AgentPort needs internet access for first-time setup and model downloads. Local AI runtimes and GGUF models can be large, so first setup can take a while.

## Startup phases

AgentPort shows each phase clearly:

1. **Preflight** — checks paths, selected model and runtime state.
2. **Prepare runtime** — writes TextGen and Harness settings.
3. **Start TextGen** — launches the local model server.
4. **Wait for API** — waits for TextGen on port `5100`.
5. **Verify model** — confirms the selected GGUF is actually loaded.
6. **Start Harness** — launches DeepSeek Harness.
7. **Ready** — opens the Harness UI.

If something fails, the progress panel and log area should show the stage that failed and the recent error output.

## GPU / RAM fit feedback

AgentPort estimates whether your selected setup should fit by looking at:

- model file size
- context length
- KV cache type
- GPU offload mode
- detected VRAM
- detected system RAM

This is a practical estimate, not a benchmark, but it helps avoid obviously bad launch settings.

## Default ports

| Component | Port |
|---|---:|
| TextGen API | `5100` |
| DeepSeek Harness UI | `3080` |

## File locations

AgentPort stores its config and profiles here:

```text
%USERPROFILE%\.dsh
```

Harness-only skills live here:

```text
%USERPROFILE%\.dsh\harness_skills
```

## Notes

- Windows only.
- GGUF models are not included.
- DeepSeek Harness is the main target integration in the current build.
- The tool is free and public.

## Licence

MIT.
