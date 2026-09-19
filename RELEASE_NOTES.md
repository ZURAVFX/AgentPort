# AgentPort 3.0.0

AgentPort 3 focuses on Codex Desktop and DeepSeek Harness integration.

- Adds AgentPort models beside Codex's built-in GPT catalogue while preserving
  Codex account authentication.
- Adds a loopback compatibility layer for DeepSeek/local model traffic and
  Codex compaction checkpoints.
- Installs a narrowly scoped AgentPort Codex skill for native tool use.
- Adds managed CUDA llama.cpp update detection with explicit confirmation,
  official SHA-256 verification and side-by-side rollback safety.
- Keeps Ollama and LM Studio as optional external runtimes rather than the
  recommended AgentPort path.
- Marks other harness integrations as beta until fully tested.

Known limitation: current Codex Desktop builds can retain previous-provider
metadata in an existing task. AgentPort improves compacted-context compatibility
but cannot guarantee that every provider switch will avoid a reconnect or app
restart.
