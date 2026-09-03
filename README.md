# AgentPort

AgentPort connects **local GGUF AI models** to **DeepSeek Harness** on Windows.

It gives you one desktop app for setting up TextGen, choosing a local model, checking GPU/RAM fit, and wiring that model into DeepSeek Harness without manually editing config files or juggling launch scripts.

## Current release

**v1.6.0** focuses on first-run setup and discovery.

- clear **Installed / Missing / Needs repair** flags for TextGen and DeepSeek Harness
- one-click **Install** and **Repair** buttons for TextGen and DeepSeek Harness
- automatic GGUF model discovery from AgentPort, TextGen, Ollama, LM Studio, Unsloth Studio, Hugging Face cache, Jan and GPT4All locations
- better handling for `mmproj` helper files used by multimodal GGUF models
- simpler Skills page with add/import/create/open/refresh actions
- fixed broken launch phase characters, for example `Phase 6 of 7 - Starting Harness`

## Download

**[Download AgentPort v1.6.0 for Windows](https://github.com/ZURAVFX/AgentPort/releases/download/v1.6.0/AgentPort_v1.6.0.exe)**

[View the v1.6.0 release notes](https://github.com/ZURAVFX/AgentPort/releases/tag/v1.6.0)

SHA-256 checksums are included with the release.

## Quick start

1. Download `AgentPort_v1.6.0.exe`.
2. Open **Settings** and check the TextGen / DeepSeek Harness flags.
3. Use **Install TextGen** and **Install Harness** if either is missing.
4. Press **Scan for models** or download/import a GGUF model.
5. Choose context length, KV cache and GPU offload mode.
6. Press **Apply & Start**.

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

External GGUF models can be launched in place. AgentPort also looks beside a selected model for `mmproj*.gguf` helper files and passes them to TextGen when found.

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

## Notes

- Windows only.
- Models are not included.
- Large models and runtimes can take a while to download.
- The GPU/RAM estimate is a launch guide, not a benchmark.

## Licence

MIT
