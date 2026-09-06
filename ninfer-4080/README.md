# AgentPort RTX 4080 NInfer backend

Experimental AgentPort backend for 16 GB RTX 4080 / RTX 4080 SUPER cards.

## What we measured on the target RTX 4080

The verified NInfer run uses the stock Qwen3.8 27B min-Q4 `.ninfer` artifact at 24,576 context, INT4 KV and MTP3:

- NInfer MTP3: about **77 tok/s** end-to-end for 256-token requests
- TextGen Ridge baseline: about **43–50 tok/s** with n-gram speculation, or about **23 tok/s** with speculation off

The NInfer provider is selected explicitly in AgentPort. TextGen remains available for arbitrary GGUF models; native TextGen MTP4/MTP6 are not enabled because they were slower on the measured 4080.

## Why NInfer is a separate backend

NInfer does **not** load GGUF. The existing `Qwen3.8-27B-Ridge-3.7bpw.gguf` stays installed and remains the TextGen fallback.

The NInfer path serves a 16 GB-specific `.ninfer` artifact of the same stock `Qwen/Qwen3.8-27B` checkpoint:

- engine fork: `aljazceru/ninfer`
- build target: CUDA `sm_89`
- artifact: `aaaljaz/qwen3.8-27b-ninfer-minq4/qwen3_8_27b_minq4.ninfer`
- device-resident weight target: about 12.7 GiB
- KV: INT4
- speculation: native MTP3
- AgentPort API: `http://127.0.0.1:5100/v1`
- API key: `local-textgen`

The engine runs in Ubuntu WSL2 because the published 16 GB fork is Linux-native. WSL forwards localhost to Windows, so DeepSeek Harness can keep using AgentPort's existing provider configuration.

## One-click install

Run:

```text
Install-NInfer4080.cmd
```

Prerequisites:

- Windows 11 + WSL2
- Ubuntu 24.04 WSL distro (default name `Ubuntu-24.04`)
- current NVIDIA Windows driver with WSL CUDA support
- RTX 4080 / 4080 SUPER 16 GB

The installer:

1. validates GPU visibility in WSL;
2. installs build dependencies;
3. installs CUDA Toolkit 13.1 in WSL if `nvcc >= 12.4` is unavailable;
4. clones the 16 GB NInfer fork;
5. explicitly builds it for `CMAKE_CUDA_ARCHITECTURES=89`;
6. validates `ninfer-serve`;
7. downloads the min-Q4 Qwen3.8 artifact;
8. sets AgentPort backend preference to `Auto`.

The first install is large because it may install CUDA plus roughly 13 GB of model data.

## AgentPort integration

The experimental Windows build is generated from the v1.6.2 source by `.release-build/v1.7.0-4080/Patch-AgentPort.ps1`.

AgentPort shows NInfer as a separate provider. Choosing **Start NInfer and open Harness** stops TextGen, starts the compatible stock min-Q4 artifact on port 5100, points Harness at it, and opens Harness when its secure link is ready. If NInfer is not installed, the same action offers the one-time setup. TextGen remains the general-purpose provider and is not silently replaced for unsupported GGUF or safetensors models.

AgentPort-managed MCP connections are optional. Missing ComfyUI, Blender, or other local MCP commands are non-fatal, so Harness can still start; unavailable connections remain disabled until their command and host application are ready.

Backend selection is stored in `%USERPROFILE%\.dsh\launcher_config.json`:

```powershell
.\Set-AgentPortBackend.ps1 -Backend Auto
.\Set-AgentPortBackend.ps1 -Backend NInfer4080
.\Set-AgentPortBackend.ps1 -Backend TextGen
```

## Real-world benchmark

Run:

```text
Run-AgentPort4080-Benchmark.cmd
```

If NInfer is not installed, the launcher offers to install it first.

The benchmark no longer repeats one deterministic prompt. It runs two separate suites:

### Fresh

Five different coding, debugging, PowerShell, architecture, and tool-planning tasks. This measures genuinely new agent work and prevents `ngram-mod` from winning by memorising a previous identical answer.

### RepetitiveAgent

Five related structured file-plan tasks with the same output schema but different projects. This deliberately measures the kind of repeated JSON/tool structure where n-gram speculation can legitimately help an agent workflow.

Default modes:

- TextGen Off
- TextGen NGram Conservative
- TextGen NGram Medium
- TextGen NGram Aggressive
- NInfer MTP3 min-Q4, when installed

Native MTP2 can still be included manually with `-IncludeNativeMtp`, but MTP4/MTP6 are intentionally omitted from the normal benchmark after the measured slowdown.

For text-only fairness, any `mmproj` command-line flag is temporarily removed from TextGen benchmark runs and restored afterwards. NInfer is also benchmarked text-only.

At the end, the script reports:

- Fresh tok/s
- Repetitive-agent tok/s
- balanced average
- VRAM usage
- a winner for each suite
- CSV summary and detailed results next to the script

## Current status

- AgentPort patched source is PowerShell parse-validated in CI.
- Windows AgentPort EXE is built in CI.
- TextGen defaults now reflect the real RTX 4080 measurements.
- NInfer setup and the OpenAI-compatible API have completed successfully on the target RTX 4080; the isolated benchmark measured about 77 tok/s with MTP3.
- Keep the PR in Draft until the packaged `v1.7.9-4080` executable has been smoke-tested on the target Windows installation with any desired MCPs enabled.
