# Astra handoff: RTX 4080 NInfer / AgentPort

Worktree branch: `feature/ninfer-rtx4080`

## Verified facts

- WSL Ubuntu-24.04, CUDA 13.1, RTX 4080 compute capability 8.9 work.
- NInfer pinned source builds for sm_89 with the Ada W8 overlay.
- Converted artifact: `~/.agentport/models/qwen3_8_27b_minq4.ninfer` (stock Qwen3.8 27B min-Q4, not Ridge).
- NInfer loads 13.47 GiB weights at 24,576-token context and serves OpenAI-compatible requests.
- Verified Fresh throughput: about 75–78 tok/s end-to-end.
- Existing TextGen baseline: about 23 tok/s off, 43–50 tok/s with NGram.
- The old benchmark header incorrectly prints the selected Ridge GGUF while NInfer loads the stock `.ninfer` artifact.

## Current commit

`126d5f6` — hardened NInfer lifecycle and added isolated benchmark.

## Files

- `ninfer-4080/NInfer.Runtime.ps1`: absolute-home WSL launch, exact-PID teardown, API identity check, early error reporting.
- `ninfer-4080/Benchmark-NInfer.ps1`: NInfer-only benchmark; tests MTP settings without restarting TextGen.
- `AgentPort-runtime-v1.7.0-4080.ps1`: installed runtime snapshot with corrected NInfer path handling and explicit min-Q4 identity.

## Astra instructions

Use minimum tool output and stop once the requested outcome is verified. Do not rerun the existing TextGen suite. First run the isolated NInfer benchmark when the host usage window permits. Then validate one real DeepSeek Harness request through AgentPort. Optimise end-to-end harness throughput, not just decoder tok/s: model identity, context/KV size, MTP draft count, prompt overhead, startup and GPU memory headroom. Keep TextGen for arbitrary GGUF/safetensors; NInfer is opt-in for supported converted artifacts. Do not claim Ridge quality or compatibility for the stock min-Q4 artifact.
