package main

import (
    "bytes"
    _ "embed"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
    "time"
    "unsafe"
)

//go:embed AgentPort_v1.6.2.ps1
var script []byte

func appendLog(path, message string) {
    f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
    if err != nil {
        return
    }
    defer f.Close()
    _, _ = fmt.Fprintf(f, "%s  %s\r\n", time.Now().Format("2006-01-02 15:04:05"), message)
}

func showError(title, message string) {
    user32 := syscall.NewLazyDLL("user32.dll")
    messageBox := user32.NewProc("MessageBoxW")
    textPtr, _ := syscall.UTF16PtrFromString(message)
    titlePtr, _ := syscall.UTF16PtrFromString(title)
    _, _, _ = messageBox.Call(
        0,
        uintptr(unsafe.Pointer(textPtr)),
        uintptr(unsafe.Pointer(titlePtr)),
        uintptr(0x10),
    )
}

func main() {
    local := os.Getenv("LOCALAPPDATA")
    if local == "" {
        home, _ := os.UserHomeDir()
        local = filepath.Join(home, "AppData", "Local")
    }

    dir := filepath.Join(local, "AgentPort")
    if err := os.MkdirAll(dir, 0755); err != nil {
        showError("AgentPort v1.6.2", "AgentPort could not create its runtime folder:\n\n"+err.Error())
        return
    }

    logPath := filepath.Join(dir, "launcher-v1.6.2.log")
    ps1 := filepath.Join(dir, "AgentPort-runtime-v1.6.2.ps1")
    appendLog(logPath, "Launcher started")

    if err := os.WriteFile(ps1, script, 0644); err != nil {
        appendLog(logPath, "Could not extract embedded runtime: "+err.Error())
        showError("AgentPort v1.6.2", "AgentPort could not extract its embedded runtime.\n\n"+err.Error()+"\n\nLog: "+logPath)
        return
    }
    appendLog(logPath, "Embedded runtime extracted to "+ps1)

    windir := os.Getenv("WINDIR")
    powershell := filepath.Join(windir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    if windir == "" {
        powershell = "powershell.exe"
    }
    if _, err := os.Stat(powershell); err != nil {
        if found, lookErr := exec.LookPath("powershell.exe"); lookErr == nil {
            powershell = found
        } else {
            appendLog(logPath, "Windows PowerShell was not found")
            showError("AgentPort v1.6.2", "Windows PowerShell could not be found. AgentPort requires Windows PowerShell 5.1 to launch its desktop UI.\n\nLog: "+logPath)
            return
        }
    }

    var output bytes.Buffer
    cmd := exec.Command(powershell, "-NoLogo", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", ps1)
    cmd.Stdout = &output
    cmd.Stderr = &output
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

    appendLog(logPath, "Starting Windows PowerShell in STA mode")
    err := cmd.Run()
    if err != nil {
        details := output.String()
        if details == "" {
            details = err.Error()
        }
        appendLog(logPath, "Runtime exited with error: "+details)
        showError("AgentPort v1.6.2 failed to start", "AgentPort hit a startup error instead of opening the UI.\n\n"+details+"\n\nFull log:\n"+logPath)
        return
    }

    appendLog(logPath, "AgentPort closed normally")
}
