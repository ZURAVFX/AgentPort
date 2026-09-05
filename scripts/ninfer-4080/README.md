# AgentPort RTX 4080 NInfer backend

Experimental AgentPort backend for 16 GB RTX 4080 / RTX 4080 SUPER cards.

## Why this is a separate backend

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

The engine runs in Ubuntu WSL2 because the published 16 GB fork is Linux-native. This avoids pretending that the 24 GB Windows/4090 fork is safe on a 16 GB card. Modern WSL forwards localhost to Windows, so DeepSeek Harness can keep using AgentPort's existing provider configuration.

## Install

Prerequisites:

- Windows 11 + WSL2
- Ubuntu 24.04 WSL distro (default name `Ubuntu-24.04`)
- current NVIDIA Windows driver with WSL CUDA support
- RTX 4080 / 4080 SUPER 16 GB

From PowerShell:

```powershell
cd scripts\ninfer-4080
.\Install-NInfer4080.ps1
```

The installer:

1. validates GPU visibility in WSL;
2. installs build dependencies;
3. installs CUDA Toolkit 13.1 in WSL if `nvcc >= 12.4` is unavailable;
4. clones the 16 GB NInfer fork;
5. explicitly builds it for `CMAKE_CUDA_ARCHITECTURES=89`;
6. validates `ninfer-serve`;
7. downloads the min-Q4 Qwen3.8 artifact.

## Start manually

```powershell
.\Start-NInfer4080.ps1 -Profile Balanced
```

Profiles:

| Profile | Context | KV | Speculation |
|---|---:|---|---|
| Safe | 32,768 | INT4 | MTP3 |
| Balanced | 49,152 | INT4 | MTP3 |
| Long | 98,304 | INT4 | MTP3 |

The published fork has been measured at 49k with MTP3 and can reach 122,880 with INT4 KV on a 16 GB A5000 Laptop GPU. AgentPort deliberately caps its automatic path below that maximum for Windows/WSL headroom.

## AgentPort v1.7.0-4080 integration

The experimental Windows build is generated from the v1.6.2 source by `.release-build/v1.7.0-4080/Patch-AgentPort.ps1`.

It adds two changes:

1. **NInfer Auto backend**: when the selected model is `Qwen3.8-27B-Ridge-3.7bpw.gguf`, the machine is an RTX 4080, and the WSL NInfer engine/model are installed, AgentPort launches NInfer on port 5100 instead of TextGen. If any prerequisite is missing it falls back to TextGen.
2. **Native MTP for the existing GGUF**: TextGen mode changes Qwen3.8 speculation from generic `ngram-mod` to `draft-mtp` (MTP2/MTP4/MTP6 for Conservative/Medium/Aggressive). The Ridge GGUF already contains the native MTP head.

Backend selection is stored in `%USERPROFILE%\.dsh\launcher_config.json`:

```powershell
.\Set-AgentPortBackend.ps1 -Backend Auto
.\Set-AgentPortBackend.ps1 -Backend NInfer4080
.\Set-AgentPortBackend.ps1 -Backend TextGen
```

`Auto` is the intended default.

## Benchmark fairly

Run the exact same prompt and max-token count against each backend:

```powershell
# Start normal AgentPort/TextGen first
.\Benchmark-AgentPortBackend.ps1

# Then stop TextGen and start NInfer
.\Start-NInfer4080.ps1 -Profile Balanced
.\Benchmark-AgentPortBackend.ps1
```

Use the measured end-to-end throughput on the actual RTX 4080 to decide which backend should remain the default. NInfer should not be assumed faster merely because its 4090/5090 variants are faster; the 16 GB path uses a different quant/layout and pinned-host placement.

## Current status

- AgentPort patched source is PowerShell parse-validated in CI.
- Windows AgentPort EXE is built in CI.
- The NInfer CUDA build itself cannot be GPU-run in GitHub's standard Windows CI; the installer validates/builds it on the target WSL machine.
- Keep TextGen as a fallback until the benchmark has been run on a real 4080.
