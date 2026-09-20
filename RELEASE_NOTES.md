# AgentPort v3.0.1

AgentPort puts other models inside the Codex desktop app. This release is the
rebuilt product: a smaller, tidier router with a proper desktop app on top of
it, a one-click Windows installer, and local models you can bring yourself.

## Install

Download `AgentPort-Setup-3.0.1.exe` and run it. It installs for the current
user, so there is no admin prompt, and it leaves an **AgentPort** shortcut on
your desktop. The installer carries everything the app needs to start: Node,
uv and a router checkout. You do not have to install anything first.

After it finishes, open AgentPort from the desktop shortcut and use the Codex
page to configure Codex Desktop. Restart Codex when it asks.

## What is in this release

**Codex Desktop is the main target.** AgentPort writes its managed blocks into
your Codex configuration, publishes the models you enable into the Codex model
picker, and keeps its own bookkeeping in a block it owns so your own settings
are left alone. If you were running the router this project was forked from,
AgentPort recognises those blocks and takes them over, keeping your provider
keys rather than asking for them again.

**Local models are first class.** You can start a managed Windows CUDA
llama.cpp runtime from the Local page, or install a GGUF you already have. A
model can be imported from a Hugging Face repository, from a tree or resolve
URL, or from a file on disk, and a repository with several models asks which
one you want. A separate vision projector is supported as an optional helper
and is validated on the filename before it is accepted.

**opencode Go is available as a provider.** If you have an opencode Go plan,
add the key on the providers page and its models appear in the list for you to
enable.

**Timing and context.** Tool results that are very large are shaped before they
reach a model on a routed turn, so a long build log does not eat the window.
Switching between a built-in model and a routed one in the same Codex thread
keeps working, including the compaction step.

## Under the hood

- The router is a trimmed descendant of the open source Codex router, renamed
  and repackaged as AgentPort.
- The Windows build is an NSIS one-click installer produced by electron-builder.
- The bundled Node and uv are unpacked beside your other application data
  rather than inside the app package, so an update can replace the app without
  discarding the runtimes or the router checkout.
- The automated suite is green: 331 of 331 test files, 4,234 tests, in about
  eight minutes. `npm run verify` runs the subset that covers the shipped
  surfaces in under three.

## Verifying the download

```
certutil -hashfile AgentPort-Setup-3.0.1.exe SHA256
```

Compare the result with the value in `SHA256SUMS` on the release page.

## Windows security notice

The installer is not code signed, so Windows SmartScreen may warn about an
unknown publisher. Choose **More info**, then **Run anyway** if you are happy
to proceed.
