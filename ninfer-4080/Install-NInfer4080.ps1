[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateSet('BuildOnly','BuildAndDownload')]
    [string]$Mode = 'BuildAndDownload'
)

$ErrorActionPreference = 'Stop'
$InstallerBuild = 'ninfer-4080-installer-v10-2026-09-05'
$Repo = 'https://github.com/aljazceru/ninfer.git'
$BaseCommit = '024b3ea4b91b67fdd75d8ca947e2a58a4258237b'
$AdaPortCommit = '39a6f20ca982f93adea52ed7941c3bd68af64111'
$AdaRawBase = "https://raw.githubusercontent.com/UDPSendToFailed/ninfer-4090/$AdaPortCommit"
$LinuxHome = $null
$Root = $null
$Source = $null
$Build = $null
$Models = $null
$ModelRepo = 'aaaljaz/qwen3.8-27b-ninfer-minq4'
$ModelFile = 'qwen3_8_27b_minq4.ninfer'
$CudaRoot = '/usr/local/cuda-13.1'
$Nvcc = "$CudaRoot/bin/nvcc"
$script:Stage = 'startup'

function Set-Stage {
    param([Parameter(Mandatory)][string]$Name)
    $script:Stage = $Name
    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan
}

function Convert-ToSafeText {
    param($Value)
    if($null -eq $Value){ return '' }
    $parts = @($Value | ForEach-Object { [string]$_ })
    return ($parts -join "`n")
}

function Convert-WindowsPathToWsl {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if($full -notmatch '^([A-Za-z]):\\(.*)$'){
        throw "Cannot convert Windows path to WSL mount path: $full"
    }
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2] -replace '\\','/'
    return "/mnt/$drive/$rest"
}

# Never pipe the shell program through wsl.exe stdin. sudo needs the real console stdin for
# password entry, and Windows PowerShell 5 can also re-encode native pipeline data. Write an
# LF-only temporary script on Windows and execute it through WSL's standard /mnt/<drive> mount.
# Do not call wslpath with a raw C:\ path: on some WSL/PowerShell combinations the backslashes
# are consumed as escapes before wslpath sees them (e.g. C:Usersname...), which caused v8 to fail.
function Invoke-WslBash {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$AsRoot
    )
    $normalized = (Convert-ToSafeText $Command) -replace "`r", ''
    $temp = Join-Path $env:TEMP ('agentport-wsl-' + [guid]::NewGuid().ToString('N') + '.sh')
    try {
        [IO.File]::WriteAllText($temp, ($normalized + "`n"), ([Text.UTF8Encoding]::new($false)))
        $wslPath = Convert-WindowsPathToWsl $temp
        & wsl.exe -d $Distro -- test -f $wslPath
        if($LASTEXITCODE -ne 0){
            throw "Temporary script is not visible through WSL at $wslPath (Windows path: $temp)"
        }
        $wslArgs = @('-d', $Distro)
        if($AsRoot){ $wslArgs += @('-u', 'root') }
        & wsl.exe @wslArgs -- bash $wslPath
        $code = $LASTEXITCODE
        if ($code -ne 0) { throw "WSL command failed with exit code $code.`n$normalized" }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Get-WslDistros {
    $items = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $items) { return @() }
    $out = @()
    foreach($item in @($items)){
        $s = (Convert-ToSafeText $item) -replace "`0", ''
        $s = $s -replace '^\s+|\s+$',''
        if($s){ $out += $s }
    }
    return $out
}

try {
    Write-Host "Installer build: $InstallerBuild" -ForegroundColor Green

    Set-Stage '1/10 Validate WSL distro'
    $distros = Get-WslDistros
    if ($distros -notcontains $Distro) {
        throw "WSL distro '$Distro' is not installed. Install it with: wsl --install -d $Distro"
    }
    Write-Host "WSL distro found: $Distro"

    # Resolve HOME in the selected distro once and use absolute Linux paths throughout.
    # A quoted '~' is a literal character in Bash, so it must never be used as a path root.
    $homeRaw = & wsl.exe -d $Distro -- sh -lc 'printf "%s" "$HOME"'
    if($LASTEXITCODE -ne 0){ throw "Could not resolve the Linux HOME path in '$Distro'." }
    $LinuxHome = (Convert-ToSafeText $homeRaw).Trim()
    if($LinuxHome -notmatch '^/[A-Za-z0-9._/-]+$'){
        throw "Linux HOME must be a safe absolute path, but WSL returned: '$LinuxHome'"
    }
    $Root = "$LinuxHome/.agentport"
    $Source = "$Root/ninfer-src"
    $Build = "$Source/build-sm89"
    $Models = "$Root/models"
    Write-Host "Linux home: $LinuxHome"

    Set-Stage '2/10 Validate RTX 4080 passthrough'
    $gpuRaw = & wsl.exe -d $Distro -- nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader
    $gpuLines = @(Convert-ToSafeText $gpuRaw -split "`n")
    $gpu = if($gpuLines.Count -gt 0){ $gpuLines[0] -replace '^\s+|\s+$','' }else{ '' }
    if (-not $gpu) { throw 'NVIDIA GPU is not visible inside WSL. Verify: wsl -d Ubuntu-24.04 -- nvidia-smi' }
    Write-Host "GPU: $gpu"
    if ($gpu -notmatch 'RTX 4080') { Write-Warning 'This installer is tuned for RTX 4080 / RTX 4080 SUPER (Ada sm_89).' }
    if ($gpu -match ',\s*([0-9]+)\s*MiB') {
        $vram = [int]$Matches[1]
        if ($vram -lt 15000) { throw "Only $vram MiB VRAM detected. This profile expects a 16 GB-class GPU." }
    }
    if ($gpu -match ',\s*([0-9]+\.[0-9]+)\s*$' -and $Matches[1] -ne '8.9') { Write-Warning "Compute capability $($Matches[1]) detected. This build explicitly targets sm_89." }

    Set-Stage '3/10 Validate WSL administrator access'
    & wsl.exe -d $Distro -u root -- true
    if($LASTEXITCODE -ne 0){ throw "Could not launch '$Distro' as root for system package installation." }
    Write-Host 'WSL administrator access confirmed.' -ForegroundColor Green

    Set-Stage '4/10 Install Linux build prerequisites'
    Invoke-WslBash -AsRoot @'
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git ninja-build pkg-config cmake curl wget ca-certificates \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libcurl4-openssl-dev \
  python3 python3-venv
'@

    Set-Stage '5/10 Detect or install CUDA toolkit'
    & wsl.exe -d $Distro -- test -x $Nvcc
    $hasNvcc = ($LASTEXITCODE -eq 0)
    if($hasNvcc){
        $nvccRaw = & wsl.exe -d $Distro -- $Nvcc --version
        $nvccText = Convert-ToSafeText $nvccRaw
        Write-Host "CUDA compiler already present at $Nvcc"
        Write-Host (($nvccText -split "`n")[-1])
    }else{
        Write-Host 'CUDA compiler not found at the expected CUDA 13.1 path.' -ForegroundColor DarkGray
        Write-Host 'Installing NVIDIA CUDA Toolkit 13.1 inside WSL...'
        Invoke-WslBash -AsRoot @'
set -euo pipefail
. /etc/os-release
case "${VERSION_ID}" in
  24.04) repo=ubuntu2404 ;;
  22.04) repo=ubuntu2204 ;;
  *) echo "Unsupported Ubuntu version ${VERSION_ID}; install CUDA Toolkit 12.4+ manually." >&2; exit 2 ;;
esac
cd /tmp
wget -q https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/cuda-keyring_1.1-1_all.deb -O cuda-keyring.deb
dpkg -i cuda-keyring.deb
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-toolkit-13-1
'@
        & wsl.exe -d $Distro -- test -x $Nvcc
        if($LASTEXITCODE -ne 0){ throw "CUDA package installation completed but $Nvcc does not exist or is not executable." }
        $nvccRaw = & wsl.exe -d $Distro -- $Nvcc --version
        if($LASTEXITCODE -ne 0){ throw "CUDA compiler exists at $Nvcc but could not execute." }
        $nvccText = Convert-ToSafeText $nvccRaw
        Write-Host (($nvccText -split "`n")[-1])
    }

    Set-Stage '6/10 Pin 16 GB NInfer fork revision'
    Invoke-WslBash @"
set -euo pipefail
mkdir -p '$Root' '$Models'
if [ -d '$Source/.git' ]; then
  git -C '$Source' fetch origin master --prune
else
  git clone '$Repo' '$Source'
fi
git -C '$Source' reset --hard
git -C '$Source' clean -fdx
git -C '$Source' fetch origin '$BaseCommit' --depth 1 || true
git -C '$Source' checkout --detach '$BaseCommit'
"@
    Write-Host "Pinned 16 GB fork: $BaseCommit" -ForegroundColor DarkGray

    Set-Stage '7/10 Apply RTX 4080 Ada sm_89 W8 kernel schedules'
    # The 16 GB fork was validated on sm_86. Its generic W8 exact/medium-T launch schedules still
    # instantiate static-shared-memory kernels larger than Ada's 0xc000-byte limit. Apply the full
    # W8 delta from the pinned AD102 port. Keeping this as a file overlay preserves the 16 GB fork's
    # artifact, host-pinning and min-Q4 work while bringing across every coupled W8 instantiation.
    Invoke-WslBash @"
set -euo pipefail
for relative in \
  src/ops/linear/w8/w8_config.h \
  src/ops/linear/w8/w8_rowsplit_gemm_splitk.cu \
  src/ops/linear/w8/w8_rowsplit_gemm_medium_t_splitk.cuh \
  src/ops/linear/w8/w8_rowsplit_gemm_mma.cuh \
  src/ops/linear/w8/w8_small_t.cu \
  src/ops/linear/w8/w8_small_t_mma.cuh \
  src/ops/linear_add/w8/w8_linear_add_gemm_simt.cu \
  src/ops/linear_add/w8/w8_linear_add_gemm_splitk.cu \
  src/ops/linear_pair/w8/w8_pair_gemm_splitk.cu \
  src/ops/linear_swiglu/w8/w8_linear_swiglu_gemm_splitk.cu
do
  wget -q '$AdaRawBase/'`$relative -O '$Source/'`$relative
done
grep -q 'defined(NINFER_SM89)' '$Source/src/ops/linear/w8/w8_config.h'
grep -q 'launch_w8_exact_t_composite(x, w, out, stream);' '$Source/src/ops/linear/w8/w8_rowsplit_gemm_splitk.cu'
grep -q 'sizeof(SharedStorage) <= 49152' '$Source/src/ops/linear/w8/w8_small_t_mma.cuh'
grep -q 'launch_splitk_exact' '$Source/src/ops/linear/w8/w8_small_t.cu'
printf '%s\n' '$AdaPortCommit' > '$Source/.agentport-sm89-port'
"@
    Write-Host "Applied pinned AD102 W8 schedules from: $AdaPortCommit" -ForegroundColor Green

    Set-Stage '8/10 Build NInfer for Ada sm_89'
    Invoke-WslBash @"
set -euo pipefail
rm -rf '$Build'
cmake -S '$Source' -B '$Build' -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_COMPILER=$Nvcc \
  -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DCMAKE_CUDA_FLAGS=-DNINFER_SM89=1 \
  -DCMAKE_CXX_FLAGS=-DNINFER_SM89=1 \
  -DNINFER_BUILD_APPS=ON \
  -DBUILD_TESTING=OFF \
  -DNINFER_BUILD_BENCHMARKS=OFF
cmake --build '$Build' --parallel `$(nproc) --target ninfer ninfer-serve
"@

    Set-Stage '9/10 Validate NInfer server binary'
    Invoke-WslBash "test -x '$Build/apps/ninfer-serve' && '$Build/apps/ninfer-serve' --help >/dev/null"
    Write-Host 'ninfer-serve binary validated.'

    if ($Mode -eq 'BuildAndDownload') {
        Set-Stage '10/10 Download Qwen3.8 min-Q4 NInfer artifact'
        Invoke-WslBash @"
set -euo pipefail
python3 -m venv '$Root/hf-venv'
'$Root/hf-venv/bin/pip' install -q -U huggingface_hub
'$Root/hf-venv/bin/hf' download '$ModelRepo' '$ModelFile' --local-dir '$Models'
"@
        Invoke-WslBash "test -s '$Models/$ModelFile'"
        Write-Host "Model ready: $Models/$ModelFile"
    } else {
        Set-Stage '10/10 Model download skipped (BuildOnly)'
    }

    Write-Host ''
    Write-Host 'RTX 4080 NInfer backend installed successfully.' -ForegroundColor Green
    Write-Host "Engine: $Build/apps/ninfer-serve"
    if ($Mode -eq 'BuildAndDownload') { Write-Host "Model:  $Models/$ModelFile" }
}
catch {
    Write-Host ''
    Write-Host '================ NINFER INSTALL FAILURE ================' -ForegroundColor Red
    Write-Host "Installer build: $InstallerBuild" -ForegroundColor Yellow
    Write-Host "Failed stage:    $script:Stage" -ForegroundColor Yellow
    Write-Host "Message:         $($_.Exception.Message)" -ForegroundColor Red
    if($_.InvocationInfo){
        Write-Host "Source line:     $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
        Write-Host "Position:        $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkGray
    }
    if($_.ScriptStackTrace){
        Write-Host 'Stack:' -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    Write-Host '========================================================' -ForegroundColor Red
    throw
}
