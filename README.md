# AgentPort

AgentPort connects **local GGUF AI models** to **DeepSeek Harness** on Windows.

It gives you one desktop app for setting up TextGen, choosing a local model, checking GPU/RAM fit, and wiring that model into DeepSeek Harness without manually editing config files or juggling launch scripts.

## Current release

**v1.6.2** is the current Windows build, and the first one verified to open its window on a normal Windows 11 desktop.

v1.6.2 fixes the startup failure that made v1.6.0 and v1.6.1 appear to do nothing when launched:

- **Fixed the startup crash.** The model scanner passed a comma-separated list straight to `Join-Path`, which threw before the window was ever created. AgentPort now opens reliably.
- **Home page fits on screen.** The layout was tightened and the window is clamped and centred to your screen work area, so the quick-action row is visible without scrolling and the window never opens under the taskbar.
- **Clear helper (`mmproj`) import.** Importing a local GGUF now offers to attach a projector/helper `mmproj-*.gguf` file when one isn't found beside the model, and passes `--mmproj` automatically.
- Correct version shown in the app footer.

It keeps everything from the v1.6 setup/discovery update:

- clear **Installed / Missing / Needs repair** flags for TextGen and DeepSeek Harness
- one-click **Install** and **Repair** buttons for TextGen and DeepSeek Harness
- automatic GGUF model discovery from AgentPort, TextGen, Ollama, LM Studio, Unsloth Studio, Hugging Face cache, Jan and GPT4All locations
- handling for `mmproj` helper files used by multimodal GGUF models
- simple Skills page with add / import / create / open / refresh actions
- Windows PowerShell STA runtime with a visible startup error instead of a silent exit
- launcher diagnostics written to `%LOCALAPPDATA%\AgentPort\launcher-v1.6.2.log`

## Download

**[Download AgentPort v1.6.2 for Windows](https://github.com/ZURAVFX/AgentPort/releases/download/v1.6.2/AgentPort_v1.6.2.exe)**

[View the v1.6.2 release notes](https://github.com/ZURAVFX/AgentPort/releases/tag/v1.6.2)

The `.sha256` file is optional. You do **not** need it to install or run AgentPort; it is only provided for users who want to verify the downloaded EXE.

## Quick start

1. Download `AgentPort_v1.6.2.exe`.
2. Double-click the EXE. No additional release files are required.
3. Open **Settings** and check the TextGen / DeepSeek Harness flags.
4. Use **Install TextGen** and **Install Harness** if either is missing.
5. Press **Scan for models**, or download/import a GGUF model.
6. Choose context length, KV cache and GPU offload mode.
7. Press **Apply & Start**.

First launch needs internet because TextGen, DeepSeek Harness and local models can be large downloads.

## What AgentPort manages

- TextGen local API on port `5100`
- DeepSeek Harness UI on port `3080`
- GGUF model selection
- context length and KV cache
- GPU offload mode
- basic GPU/RAM fit checks
- model import and Hugging Face GGUF download flow
- Harness-only skills folder
- runtime logs and process cleanup

## Model discovery

AgentPort scans common local AI model locations, including:

- AgentPort model folder
- TextGen `user_data/models`
- Ollama default and `OLLAMA_MODELS`
- LM Studio defaults and detected config paths
- Unsloth Studio defaults and `UNSLOTH_STUDIO_HOME`
- Hugging Face cache via `HF_HOME` / `HF_HUB_CACHE`
- Jan model folders
- GPT4All model folders

External GGUF models can be launched in place. AgentPort also looks beside a selected model for `mmproj*.gguf` helper files and passes them to TextGen when found. When you import a model whose helper isn't adjacent, AgentPort offers to pick the `mmproj` file directly.

## Skills

The Skills page is for **DeepSeek Harness-only skills**.

You can:

- add an existing skill folder
- import a skill ZIP
- create a blank `skill.md` template
- open the skills folder
- refresh the installed list

Skills are stored separately so AgentPort does not inject another agent catalogue into DeepSeek Harness.

```text
%USERPROFILE%\.dsh\harness_skills
```

## Settings and files

AgentPort stores persistent settings here:

```text
%USERPROFILE%\.dsh
```

Main local runtime folders default to:

```text
%PUBLIC%\AgentPort\textgen
%PUBLIC%\AgentPort\models
%LOCALAPPDATA%\AgentPort\harness-workspace
```

If AgentPort ever fails during startup, check:

```text
%LOCALAPPDATA%\AgentPort\launcher-v1.6.2.log
```

## Building from source

The v1.6.2 EXE is reproducible from `.release-build/v1.6.2/` (fixed PowerShell app, Go launcher, icon resource). See [`.release-build/v1.6.2/BUILD.md`](.release-build/v1.6.2/BUILD.md). CI can rebuild it from the **Build and release AgentPort v1.6.2** workflow (manual dispatch).

## Notes

- Windows only.
- Models are not included.
- Large models and runtimes can take a while to download.
- The GPU/RAM estimate is a launch guide, not a benchmark.

## Licence

MIT
