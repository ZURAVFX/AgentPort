# AgentPort v2.0 release checklist

This is the release gate. A backend connecting or producing a high token rate is not enough: a fresh user must be able to reach a useful agent, complete real MCP work and recover from common failures without separate instructions.

## A. Backend and model evidence

- [x] Build NInfer for Ada `sm_89` and verify its OpenAI-compatible server on the RTX 4080.
- [x] Measure NInfer at roughly 75-80 tok/s with its compatible 27B min-Q4 artifact.
- [x] Verify Ridge 27B runs at 48k and completes real ComfyUI and Blender tasks without repeated `continue` prompts.
- [x] Measure Qwen 9B at roughly 90 tok/s and reject it after it produced an invalid ComfyUI workflow.
- [x] Research credible 16 GB candidates before downloading: Qwen3-Coder 30B-A3B, GPT-OSS 20B and GLM-4.7 Flash.
- [x] Run bounded candidate gates and reject GPT-OSS/GLM after unreliable or wandering tool behaviour.
- [x] Run the official Qwen3-Coder through one combined 48k session: create, validate and execute a ComfyUI workflow, then modify and independently verify a Blender 5.2 scene.
- [x] Select Qwen3-Coder 30B-A3B IQ3_XXS as the 16 GB default: all gates passed in five autonomous turns at a weighted decoder rate of about 104 tok/s.
- [x] Keep Ridge and arbitrary GGUF support available but unverified in the chooser; keep NInfer as an advanced specialist option because its 16 GB context ceiling is lower.

## B. One-click user experience

- [x] Replace internal terms such as `Team`, `TextGen` and port numbers with user-facing outcomes on Home.
- [x] Make Home show the detected GPU, recommended install, active model and one primary next action.
- [x] Clearly separate `Download and start recommended` from `Use an existing GGUF`.
- [x] Discover compatible existing GGUF files without presenting them as pre-verified.
- [x] Automatically select the chosen model in Harness and install the concise action-first preset.
- [x] Put ComfyUI, Blender and generic folder-free MCP JSON setup in one guided manager with Test, Save and repair guidance.
- [x] Keep Harness skills separate from MCP connections.
- [x] Keep NInfer, legacy runtimes, Hugging Face downloads and manual tuning behind Advanced sections.
- [x] Show download/start phases, actionable errors, live RAM/VRAM and measured token statistics.
- [x] Make Stop stack, Restart and model switching dependable from Home.
- [x] Bring the window to the foreground when launched normally.

## C. Fresh-user and failure gates

- [x] Back up and clear old custom TextGen and AgentPort presets without deleting model files.
- [x] Reset only AgentPort-owned preferences; preserve MCP configuration, credentials, creative-app data and unrelated Harness providers.
- [x] Verify the no-model call to action, discovered-model path and checksum-verified recommended installer path.
- [x] Provide clear recovery for missing Harness, missing/closed creative apps and unavailable MCP connectors.
- [x] Guard insufficient GPU/RAM/disk, occupied ports, interrupted/resumed downloads and repeated clicks.
- [x] Remove the hidden dependency on a writable legacy TextGen log folder.
- [x] Verify packaged EXE start, clean stop, restart and final cleanup with the real 48k model and Harness.
- [x] Verify closing or stopping AgentPort leaves the separately running ComfyUI and Blender application processes alive.
- [x] Inspect Home, Models, Skills & MCPs and Settings, including the minimum supported window size.
- [x] Run the interface craft-floor check with no remaining findings.

## D. Release

- [x] Build the stable packaged EXE on `feature/ninfer-rtx4080`.
- [x] Parse every shipped PowerShell file, compile the MCP Python helpers and build the Go launcher.
- [x] Verify the installer model/runtime checksum and packaged UI smoke test.
- [x] Record exact tested hardware separately from expected RTX 30/40 compatibility.
- [x] Record the final EXE path, hash and concise release notes.

## Final decision

The default is the official Qwen3-Coder 30B-A3B Instruct IQ3_XXS GGUF at 49,152 context through AgentPort's managed llama.cpp runtime. It was both faster and more reliable for the tested agent work than the alternatives. NInfer remains available under Advanced for its compatible converted model, but it is not the default because its usable 16 GB context is lower.
