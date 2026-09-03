package main

import (
    _ "embed"
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
)

//go:embed AgentPort_v1.6.0.ps1
var script []byte

func main() {
    local := os.Getenv("LOCALAPPDATA")
    if local == "" {
        home, _ := os.UserHomeDir()
        local = filepath.Join(home, "AppData", "Local")
    }
    dir := filepath.Join(local, "AgentPort")
    _ = os.MkdirAll(dir, 0755)
    ps1 := filepath.Join(dir, "AgentPort-runtime-v1.6.0.ps1")
    _ = os.WriteFile(ps1, script, 0644)

    cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1)
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    _ = cmd.Run()
}
