# AgentPort 1.7.9: RTX 4080 NInfer

1. Extract the release ZIP into a folder.
2. Open `AgentPort-v1.7.9-4080.exe`.
3. Choose **Qwen3.8 27B min-Q4 | NInfer RTX 4080**, choose 24k for maximum speed or 49k for maximum context, then press **Start NInfer and open Harness**. AgentPort stops TextGen, loads the matching model, makes NInfer the Harness default and opens Harness automatically.
4. If NInfer is not installed, the same start button offers the one-time setup. Setup and repair are also available under **Models**.
5. Open **Skills & MCPs** to add Harness skills, choose a folder connection or import standard `mcpServers` JSON. NInfer automatically keeps oversized MCP tool lists out of its 24k fast profile, preserving a usable context; TextGen can use the full tool set.
6. In **Skills & MCPs**, choose **Install & make default** under **Zura Low Thinking**. This copies the preset to `%USERPROFILE%\.dsh\.agent-presets\zura-low-thinking\agent.cordis.yml`, backs up any existing copy, sets it as the Harness default and keeps Ralph to eight rounds. Restart Harness when prompted; existing chats keep their current preset.
7. If Harness behaves oddly or **New chat** does not respond, click **Update Harness** on Home. AgentPort checks and caches the latest published Harness package, switches away from an older local checkout without deleting it, and restarts Harness while keeping the selected model running.

### Priority MCPs

In **Skills & MCPs → MCP connections**, **Add ComfyUI** creates the local `comfy-mcp` connection. The user needs Python 3.10+, `comfy-cli` 1.14+, a ComfyUI workspace, and the `comfy-mcp` package. ComfyUI must be left running. The official local setup is documented at <https://docs.comfy.org/agent-tools/mcp#installation>.

**Add Blender** creates the `blender-mcp` connection. The user needs Blender 5.1+, the official Blender Lab MCP add-on installed and started inside Blender, plus the MCP server command installed. The official instructions and security warning are at <https://www.blender.org/lab/mcp-server/>. Do not use an older community Blender add-on with the official Lab server: they use different protocols.

For any other MCP, use **Import an MCP configuration** and paste its standard `mcpServers` JSON. AgentPort also accepts the common `servers` and `serverUrl` variants, validates names and HTTP URLs, allows each connection to be disabled or removed, and stores secrets only in the user's local `.dsh` configuration.

For the RTX 4080 24k NInfer fast profile, oversized MCP tool catalogues are automatically omitted from the NInfer prompt. This prevents the common 26k-token context rejection that makes a new Harness chat appear unresponsive. TextGen remains available when full MCP tool access is required.

NInfer loads the converted stock Qwen3.8 27B min-Q4 artifact. It does not load the Ridge GGUF. The fast profile uses 24,576 context, INT4 KV, concurrency 1 and MTP3. The 49,152-token profile is the largest allocation verified on this RTX 4080 and left approximately 114 MiB free after startup; 65,536 failed to allocate. The NInfer coding profile excludes globally configured MCP clients and background AI title generation by default to reduce prompt size and competing requests. AgentPort-managed MCP tool catalogues are automatically suppressed for the 24k NInfer profile when they would exceed context; use TextGen for full MCP access. Core coding tools remain available.

This pinned 16 GB Ada fork publishes one practical artifact for this card: Qwen3.8 27B min-Q4. Upstream NInfer lists additional Qwen3.6/3.8 artifacts, but their files are 16.29 to 21.22 GiB before runtime memory and do not fit this verified 16 GB resident profile. AgentPort therefore does not advertise them as compatible downloads.

## Measured on this RTX 4080

Six 256-token requests per setting, temperature 0, including prompt processing and HTTP time. Reasoning tokens count towards completion usage.

| NInfer setting | Weighted tok/s |
|---|---:|
| MTP3 | 77.17 |
| MTP5 | 54.57 |
| Speculation off | 39.42 |

MTP3 completed both Fresh and RepetitiveAgent suites. The prior TextGen Ridge NGram results were approximately 43–50 tok/s. The measured throughput improvement is about 54–79%, but model weights and context differ, so this does not establish equivalent quality or performance on identical workloads.

The real DeepSeek Harness headless profile used AgentPort's settings writer and shared NInfer launcher, called a shell tool, and returned 323 for 17 × 19. Its initial 37,775-token prompt exceeded the local context; excluding external MCP clients brought it to roughly 13,800 tokens. Such long prompts still take tens of seconds to process. The 77 tok/s figure is not whole-task Harness throughput. Stock-model coding quality and long-session behaviour have not been exhaustively evaluated.

Run `ninfer-4080/Run-AgentPort4080-Benchmark.cmd` for the NInfer-only benchmark. Results are saved after every sample under `ninfer-4080/results`. The old v2 PowerShell entry point redirects to this test by default.

Build the executable from source with `go build -ldflags "-H=windowsgui" -o AgentPort-v1.7.9-4080.exe main.go`. The EXE extracts its bundled scripts into `%LOCALAPPDATA%/AgentPort/v1.7.9-4080`. Startup diagnostics are in that folder's `launcher.log`.

Work is on `feature/ninfer-rtx4080`; no public push or main-branch change was made. This repository includes an imported installed AgentPort runtime, so review it against the canonical application repository before publishing.
