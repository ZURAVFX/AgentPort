# AgentPort 1.8.0: RTX 4080 NInfer

1. Extract the release ZIP into a folder.
2. Open `AgentPort-v1.8.0-4080.exe`.
3. Choose **Qwen3.8 27B min-Q4 | NInfer RTX 4080**, then choose 48k (recommended) for best long-context usability. Use 32k Tools for MCP work when VRAM is tight, or 24k Fast for speed-only mode. Press **Start NInfer and open Harness**. AgentPort stops its previous stack, loads the matching model, makes NInfer the Harness default and opens Harness automatically.
4. If NInfer is not installed, the same start button offers the one-time setup. Setup and repair are also available under **Models**.
5. Open **Skills & MCPs** to add Harness skills, choose a ready-made MCP connection or import standard `mcpServers` JSON. Skills are instructions; MCPs are callable tools. ComfyUI needs the MCP connection, not a matching skill.
6. In **Skills & MCPs**, choose **Install / repair** under **Zura Fast**. This installs valid preset metadata, makes it the default for new chats and limits Ralph to eight rounds. Restart Harness when prompted; existing chats keep their current preset.
7. If Harness behaves oddly or **New chat** does not respond, open **Settings** and choose **Update to latest**. AgentPort refreshes the published Harness package without deleting a local source checkout.

### Priority MCPs

In **Skills & MCPs → MCP connections**, **Add ComfyUI** creates the local `comfy-mcp` connection. The user needs Python 3.10+, `comfy-cli` 1.14+, a ComfyUI workspace, and the `comfy-mcp` package. ComfyUI must be left running. The official local setup is documented at <https://docs.comfy.org/agent-tools/mcp#installation>.

**Add Blender** creates the `blender-mcp` connection. The user needs Blender 5.1+, the official Blender Lab MCP add-on installed and started inside Blender, plus the MCP server command installed. The official instructions and security warning are at <https://www.blender.org/lab/mcp-server/>. Do not use an older community Blender add-on with the official Lab server: they use different protocols.

For any other MCP, use **Import an MCP configuration** and paste its standard `mcpServers` JSON. AgentPort also accepts the common `servers` and `serverUrl` variants, validates names and HTTP URLs, allows each connection to be disabled or removed, and stores secrets only in the user's local `.dsh` configuration.

For the RTX 4080 24k Fast profile, MCP tool catalogues are omitted from the prompt. This prevents the common 26k-token context rejection that makes a new Harness chat appear unresponsive. Use 32k Tools as the practical MCP mode when 48k context is too tight on VRAM. Use 48k (49,152 tokens) as the normal starting point where possible. AgentPort's managed llama.cpp runtime loads ordinary GGUF models directly.

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

Build the executable from source with `go build -ldflags "-H=windowsgui" -o AgentPort-v1.8.0-4080.exe main.go`. The EXE extracts its bundled scripts into `%LOCALAPPDATA%/AgentPort/v1.8.0-4080`. Startup diagnostics are in that folder's `launcher.log`.

Work is on `feature/ninfer-rtx4080`; no public push or main-branch change was made. This repository includes an imported installed AgentPort runtime, so review it against the canonical application repository before publishing.
