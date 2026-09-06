package main

import (
    "embed"
    "io/fs"
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
)

//go:embed AgentPort-runtime-v1.7.0-4080.ps1 ninfer-4080/*.ps1 ninfer-4080/*.cmd
var files embed.FS

func main() {
    root := filepath.Join(os.Getenv("LOCALAPPDATA"), "AgentPort", "v1.8.0-4080")
    err := fs.WalkDir(files, ".", func(path string, entry fs.DirEntry, walkErr error) error {
        if walkErr != nil { return walkErr }
        target := filepath.Join(root, filepath.FromSlash(path))
        if entry.IsDir() { return os.MkdirAll(target, 0755) }
        data, err := files.ReadFile(path)
        if err != nil { return err }
        return os.WriteFile(target, data, 0644)
    })
    if err != nil { return }
    log, err := os.OpenFile(filepath.Join(root, "launcher.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
    if err != nil { return }
    defer log.Close()
    args := []string{"-NoLogo", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", filepath.Join(root, "AgentPort-runtime-v1.7.0-4080.ps1")}
    if len(os.Args) > 1 && os.Args[1] == "--smoke-test" { args = append(args, "-SmokeTest") }
    if len(os.Args) > 1 && os.Args[1] == "--integration-test" { args = append(args, "-IntegrationTest") }
    command := exec.Command("powershell.exe", args...)
    command.SysProcAttr = &syscall.SysProcAttr{HideWindow:true}
    command.Stdout = log
    command.Stderr = log
    if err := command.Run(); err != nil { log.WriteString(err.Error()+"\n") }
}
