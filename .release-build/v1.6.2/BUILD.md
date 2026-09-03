# AgentPort v1.6.2 build inputs

This folder rebuilds the **working** v1.6.2 Windows EXE. Unlike the v1.6.0/v1.6.1
inputs (which stored the PowerShell app as base64/xz chunks and reconstructed it
in CI), the fixed application source is stored here directly and verified to open
a real WPF window on a normal Windows 11 desktop.

## Contents

| File | Purpose |
|---|---|
| `AgentPort_v1.6.2.ps1` | The full PowerShell/WPF application (embedded into the EXE). |
| `main.go` | Go launcher that extracts and runs the script under Windows PowerShell (STA), with a launcher log and a visible startup error path. Embeds `AgentPort_v1.6.2.ps1`. |
| `rsrc_amd64.syso.b64` | Base64 of the Windows icon resource object linked into the EXE. |

## What v1.6.2 fixes over v1.6.1

- **Startup crash**: `Get-ModelSearchRoots` passed a comma-separated list straight to
  `Join-Path`, so `ChildPath` became an array and the app threw before the window
  opened (`Cannot convert 'System.Object[]' ... required by parameter 'ChildPath'`).
  This is why v1.6.0/v1.6.1 "did nothing" on a real PC. The list is now built with
  parenthesised `Join-Path` calls.
- **Home page layout**: the page no longer overflows — the bottom quick-action row is
  visible without scrolling, and the window is clamped to the screen work area and
  centred so it never opens below the taskbar.
- **Version label**: the sidebar footer now reads the real version (was hard-coded
  `v1.6.0`).
- **Import GGUF + helper**: importing a local GGUF now clearly offers to attach a
  projector/helper (`mmproj-*.gguf`) file when one isn't found next to the model.

## Rebuild locally (Windows, PowerShell 5.1 + Go)

```powershell
# from this folder
[Convert]::FromBase64String((Get-Content .\rsrc_amd64.syso.b64 -Raw) -replace '\s','') |
  Set-Content -Encoding Byte .\rsrc_amd64.syso
go mod init agentport/release-build-v162   # first time only
go build -trimpath -ldflags '-s -w -H=windowsgui' -o AgentPort_v1.6.2.exe .
```

The build is a GUI subsystem EXE (`-H=windowsgui`) so no console window appears.
