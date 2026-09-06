# AgentPort 1.7.3: RTX 4080 NInfer

1. Extract the release ZIP into a folder.
2. Run `ninfer-4080/Install-NInfer4080.cmd` once. Existing matching installations are reused. A new WSL installation may require a reboot and initial Ubuntu account setup. Initial CUDA and model downloads are large; the artifact is approximately 16 GB on disk.
3. Close other loaded local models and GPU applications. Keep roughly 14.6 GB of GPU memory free.
4. Open `AgentPort-v1.7.3-4080.exe`. Select **Qwen3.8 27B min-Q4 | NInfer RTX 4080** and press **Apply & Start**. Close an existing Harness before switching profiles.
5. Keep AgentPort open while using NInfer. Closing it or choosing Offload stops its NInfer instance. Other selected GGUF models use the existing TextGen path.

NInfer loads the converted stock Qwen3.8 27B min-Q4 artifact. It does not load the Ridge GGUF. The selected profile uses 24,576 context, INT4 KV, concurrency 1 and MTP3. The NInfer coding profile excludes globally configured MCP clients and background AI title generation to reduce prompt size and competing requests. Existing global configurations remain on disk; use the regular Harness profile for those integrations. Core coding tools remain available.

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

Build the executable from source with `go build -ldflags "-H=windowsgui" -o AgentPort-v1.7.3-4080.exe main.go`. The EXE extracts its bundled scripts into `%LOCALAPPDATA%/AgentPort/v1.7.3-4080`. Startup diagnostics are in that folder's `launcher.log`.

Work is on `feature/ninfer-rtx4080`; no public push or main-branch change was made. This repository includes an imported installed AgentPort runtime, so review it against the canonical application repository before publishing.
