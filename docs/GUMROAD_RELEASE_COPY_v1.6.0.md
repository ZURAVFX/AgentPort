# AgentPort v1.6.0 Gumroad copy

## Title
AgentPort v1.6.0 - local GGUF models to DeepSeek Harness

## Short description
AgentPort connects local GGUF AI models to DeepSeek Harness on Windows. v1.6.0 makes setup clearer with install status flags, one-click TextGen/Harness install buttons, smarter model discovery, better mmproj handling and a simpler Skills page.

## Update notes
AgentPort v1.6.0 is focused on first-run setup and model discovery:

- Added clear Installed / Missing / Needs repair flags for TextGen and DeepSeek Harness.
- Added one-click Install and Repair buttons for TextGen and DeepSeek Harness.
- Added model scanning for AgentPort, TextGen, Ollama, LM Studio, Unsloth Studio, Hugging Face cache, Jan and GPT4All locations.
- Added helper-file handling for multimodal GGUF models using nearby `mmproj*.gguf` files.
- Reworked the Skills page with Add skill folder, Import skill ZIP, Create blank skill, Open skills folder and Refresh actions.
- Fixed broken phase text characters, including the `Â·` issue in launch progress.

## Support note
First launch can take time because TextGen, DeepSeek Harness and local models are large downloads. If setup fails, open the AgentPort log panel and check the exact phase shown.
