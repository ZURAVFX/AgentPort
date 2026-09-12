package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

//go:embed AgentPort-runtime-v1.7.0-4080.ps1 ninfer-4080/*.ps1 ninfer-4080/*.cmd ninfer-4080/*.py ninfer-4080/*.js ninfer-4080/vendor/yaml
var files embed.FS

const appVersion = "2.2.5"
const releaseAPI = "https://api.github.com/repos/ZURAVFX/AgentPort/releases/latest"

type githubRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

func versionNumber(value string) (int64, bool) {
	value = strings.TrimPrefix(strings.TrimSpace(value), "v")
	parts := strings.Split(value, ".")
	if len(parts) != 3 {
		return 0, false
	}
	major, e1 := strconv.ParseInt(parts[0], 10, 32)
	minor, e2 := strconv.ParseInt(parts[1], 10, 32)
	patch, e3 := strconv.ParseInt(parts[2], 10, 32)
	if e1 != nil || e2 != nil || e3 != nil || major < 0 || minor < 0 || patch < 0 {
		return 0, false
	}
	return major*1000000 + minor*1000 + patch, true
}

func updateBeforeStart(args []string) bool {
	for _, arg := range args {
		if strings.HasPrefix(arg, "--") && (arg == "--smoke-test" || arg == "--integration-test" || arg == "--integration-current-model") {
			return false
		}
	}
	current, ok := versionNumber(appVersion)
	if !ok {
		return false
	}
	client := &http.Client{Timeout: 3 * time.Second}
	req, err := http.NewRequest(http.MethodGet, releaseAPI, nil)
	if err != nil {
		return false
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "AgentPort/"+appVersion)
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	var release githubRelease
	if json.NewDecoder(resp.Body).Decode(&release) != nil {
		return false
	}
	target, ok := versionNumber(release.TagName)
	if !ok || target <= current {
		return false
	}
	var exeURL, hashURL string
	for _, asset := range release.Assets {
		if asset.Name == "AgentPort.exe" {
			exeURL = asset.BrowserDownloadURL
		}
		if asset.Name == "AgentPort.exe.sha256" {
			hashURL = asset.BrowserDownloadURL
		}
	}
	if exeURL == "" || hashURL == "" {
		return false
	}
	root := filepath.Join(os.Getenv("LOCALAPPDATA"), "AgentPort", "updates")
	if os.MkdirAll(root, 0755) != nil {
		return false
	}
	tmp := filepath.Join(root, "AgentPort-"+strings.TrimPrefix(release.TagName, "v")+".exe.download")
	final := strings.TrimSuffix(tmp, ".download")
	if err := downloadTo(client, exeURL, tmp); err != nil {
		_ = os.Remove(tmp)
		return false
	}
	hashResp, err := client.Get(hashURL)
	if err != nil {
		_ = os.Remove(tmp)
		return false
	}
	defer hashResp.Body.Close()
	hashText, err := io.ReadAll(io.LimitReader(hashResp.Body, 4096))
	if err != nil {
		_ = os.Remove(tmp)
		return false
	}
	want := strings.ToLower(strings.Fields(string(hashText))[0])
	file, err := os.Open(tmp)
	if err != nil {
		_ = os.Remove(tmp)
		return false
	}
	sum := sha256.New()
	_, copyErr := io.Copy(sum, file)
	_ = file.Close()
	if copyErr != nil || len(want) != 64 || hex.EncodeToString(sum.Sum(nil)) != want {
		_ = os.Remove(tmp)
		return false
	}
	if os.Rename(tmp, final) != nil {
		_ = os.Remove(tmp)
		return false
	}
	currentExe, err := os.Executable()
	if err != nil {
		return false
	}
	pid := os.Getpid()
	script := "$p=Get-Process -Id " + strconv.Itoa(pid) + " -ErrorAction SilentlyContinue; if($p){$p.WaitForExit(15000)}; Move-Item -LiteralPath '" + strings.ReplaceAll(final, "'", "''") + "' -Destination '" + strings.ReplaceAll(currentExe, "'", "''") + "' -Force; Start-Process -FilePath '" + strings.ReplaceAll(currentExe, "'", "''") + "'"
	if err := exec.Command("powershell.exe", "-NoProfile", "-WindowStyle", "Hidden", "-Command", script).Start(); err != nil {
		return false
	}
	return true
}

func downloadTo(client *http.Client, url, path string) error {
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return io.ErrUnexpectedEOF
	}
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = io.Copy(file, resp.Body)
	return err
}

func main() {
	if updateBeforeStart(os.Args[1:]) {
		return
	}
	root := filepath.Join(os.Getenv("LOCALAPPDATA"), "AgentPort", "v2.2.5")
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
	if len(os.Args) > 1 && os.Args[1] == "--integration-current-model" {
		args = append(args, "-IntegrationCurrentModel")
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
