package main

import (
	"embed"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"unsafe"
)

//go:embed AgentPort-runtime-v1.7.0-4080.ps1 ninfer-4080/*.ps1 ninfer-4080/*.cmd ninfer-4080/*.py
var files embed.FS

func main() {
	root := filepath.Join(os.Getenv("LOCALAPPDATA"), "AgentPort", "v2.0.6")
	err := fs.WalkDir(files, ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		target := filepath.Join(root, filepath.FromSlash(path))
		if entry.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		data, err := files.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, data, 0644)
	})
	if err != nil {
		return
	}
	log, err := os.OpenFile(filepath.Join(root, "launcher.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer log.Close()
	args := []string{"-NoLogo", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", filepath.Join(root, "AgentPort-runtime-v1.7.0-4080.ps1")}
	if len(os.Args) > 1 && os.Args[1] == "--smoke-test" {
		args = append(args, "-SmokeTest")
	}
	if len(os.Args) > 1 && os.Args[1] == "--integration-test" {
		args = append(args, "-IntegrationTest")
	}
	command := exec.Command("powershell.exe", args...)
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	command.Stdout = log
	command.Stderr = log
	if err := command.Start(); err != nil {
		log.WriteString(err.Error() + "\n")
		return
	}
	job := createKillOnCloseJob()
	if job != 0 {
		assignPIDToJob(job, command.Process.Pid)
	}
	exitCode := 0
	if err := command.Wait(); err != nil {
		log.WriteString(err.Error() + "\n")
		if exitError, ok := err.(*exec.ExitError); ok {
			exitCode = exitError.ExitCode()
		} else {
			exitCode = 1
		}
	}
	if job != 0 {
		syscall.CloseHandle(job)
	}
	if exitCode != 0 {
		log.Close()
		os.Exit(exitCode)
	}
}

const jobObjectLimitKillOnJobClose = 0x00002000

type jobObjectBasicLimitInformation struct {
	PerProcessUserTimeLimit int64
	PerJobUserTimeLimit     int64
	LimitFlags              uint32
	MinimumWorkingSetSize   uintptr
	MaximumWorkingSetSize   uintptr
	ActiveProcessLimit      uint32
	Affinity                uintptr
	PriorityClass           uint32
	SchedulingClass         uint32
}

type ioCounters struct {
	ReadOperationCount  uint64
	WriteOperationCount uint64
	OtherOperationCount uint64
	ReadTransferCount   uint64
	WriteTransferCount  uint64
	OtherTransferCount  uint64
}

type jobObjectExtendedLimitInformation struct {
	BasicLimitInformation jobObjectBasicLimitInformation
	IoInfo                ioCounters
	ProcessMemoryLimit    uintptr
	JobMemoryLimit        uintptr
	PeakProcessMemoryUsed uintptr
	PeakJobMemoryUsed     uintptr
}

var kernel32 = syscall.NewLazyDLL("kernel32.dll")
var createJobObject = kernel32.NewProc("CreateJobObjectW")
var setInformationJobObject = kernel32.NewProc("SetInformationJobObject")
var assignProcessToJob = kernel32.NewProc("AssignProcessToJobObject")
var openProcess = kernel32.NewProc("OpenProcess")

func createKillOnCloseJob() syscall.Handle {
	handle, _, _ := createJobObject.Call(0, 0)
	if handle == 0 {
		return 0
	}
	info := jobObjectExtendedLimitInformation{}
	info.BasicLimitInformation.LimitFlags = jobObjectLimitKillOnJobClose
	ok, _, _ := setInformationJobObject.Call(handle, 9, uintptr(unsafe.Pointer(&info)), unsafe.Sizeof(info))
	if ok == 0 {
		syscall.CloseHandle(syscall.Handle(handle))
		return 0
	}
	return syscall.Handle(handle)
}

func assignPIDToJob(job syscall.Handle, pid int) {
	const processTerminateAndSetQuota = 0x0001 | 0x0100
	process, _, _ := openProcess.Call(processTerminateAndSetQuota, 0, uintptr(pid))
	if process == 0 {
		return
	}
	defer syscall.CloseHandle(syscall.Handle(process))
	assignProcessToJob.Call(uintptr(job), process)
}
