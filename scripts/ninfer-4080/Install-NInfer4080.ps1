[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateSet('BuildOnly','BuildAndDownload')]
    [string]$Mode = 'BuildAndDownload'
)

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/aljazceru/ninfer.git'
$Root = '~/.agentport'
$Source = "$Root/ninfer-src"
$Build = "$Source/build-sm89"
$Models = "$Root/models"
$ModelRepo = 'aaaljaz/qwen3.8-27b-ninfer-minq4'
$ModelFile = 'qwen3_8_27b_minq4.ninfer'

function Invoke-WslBash {
    param([Parameter(Mandatory)][string]$Command)
    & wsl.exe -d $Distro -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) { throw "WSL command failed with exit code $LASTEXITCODE.`n$Command" }
}

function Get-WslDistros {
    $items = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    @($items | ForEach-Object { ($_ -replace "`0",'').Trim() } | Where-Object { $_ })
}

$distros = Get-WslDistros
if ($distros -notcontains $Distro) {
    throw "WSL distro '$Distro' is not installed. Install it first with: wsl --install -d $Distro"
}

Write-Host 'Checking NVIDIA GPU exposed to WSL...'
$gpu = (& wsl.exe -d $Distro -- bash -lc "nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader 2>/dev/null | head -n1").Trim()
if (-not $gpu) { throw 'NVIDIA GPU is not visible inside WSL. Update the NVIDIA Windows driver and verify `wsl nvidia-smi` works.' }
Write-Host "GPU: $gpu"
if ($gpu -notmatch 'RTX 4080') {
    Write-Warning 'This installer is tuned for RTX 4080 / 4080 SUPER (Ada sm_89). Continuing because other sm_89 cards may also work.'
}
if ($gpu -match ',\s*([0-9]+)\s*MiB') {
    $vram = [int]$Matches[1]
    if ($vram -lt 15000) { throw "Only $vram MiB VRAM detected. The 27B min-Q4 profile expects a 16 GB-class GPU." }
}
if ($gpu -match ',\s*([0-9]+\.[0-9]+)\s*$' -and $Matches[1] -ne '8.9') {
    Write-Warning "Compute capability $($Matches[1]) detected. This build explicitly targets sm_89."
}

Write-Host 'Installing Linux build prerequisites...'
Invoke-WslBash @'
set -euo pipefail
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git ninja-build pkg-config cmake curl wget ca-certificates \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libcurl4-openssl-dev \
  python3 python3-venv
'@

$nvccVersion = (& wsl.exe -d $Distro -- bash -lc "if command -v nvcc >/dev/null 2>&1; then nvcc --version | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | tail -n1; fi").Trim()
$needCuda = $true
if ($nvccVersion) {
    try { if ([version]$nvccVersion -ge [version]'12.4') { $needCuda = $false } } catch {}
}

if ($needCuda) {
    Write-Host 'CUDA toolkit 12.4+ not found in WSL. Installing NVIDIA CUDA Toolkit 13.1...'
    Invoke-WslBash @'
set -euo pipefail
. /etc/os-release
case "${VERSION_ID}" in
  24.04) repo=ubuntu2404 ;;
  22.04) repo=ubuntu2204 ;;
  *) echo "Unsupported Ubuntu version ${VERSION_ID}; install CUDA Toolkit 12.4+ manually." >&2; exit 2 ;;
esac
cd /tmp
wget -q https://developer.download.nvidia.com/compute/cuda/repos/${repo}/x86_64/cuda-keyring_1.1-1_all.deb -O cuda-keyring.deb
sudo dpkg -i cuda-keyring.deb
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-toolkit-13-1
'@
}

Write-Host 'Cloning/updating the 16 GB NInfer fork...'
Invoke-WslBash @"
set -euo pipefail
mkdir -p $Root $Models
if [ -d $Source/.git ]; then
  git -C $Source fetch --all --prune
  git -C $Source reset --hard origin/master
else
  git clone --branch master --depth 1 $Repo $Source
fi
"@

Write-Host 'Configuring NInfer specifically for Ada sm_89...'
Invoke-WslBash @"
set -euo pipefail
export PATH=/usr/local/cuda-13.1/bin:/usr/local/cuda/bin:`$PATH
cmake -S $Source -B $Build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES=89 \
  -DNINFER_BUILD_APPS=ON \
  -DBUILD_TESTING=OFF \
  -DNINFER_BUILD_BENCHMARKS=OFF
cmake --build $Build --parallel `$(nproc) --target ninfer ninfer-serve
"@

Write-Host 'Validating the sm_89 server binary...'
Invoke-WslBash "test -x $Build/apps/ninfer-serve && $Build/apps/ninfer-serve --help >/dev/null"

if ($Mode -eq 'BuildAndDownload') {
    Write-Host 'Downloading the 16 GB Qwen3.8 min-Q4 NInfer artifact...'
    Invoke-WslBash @"
set -euo pipefail
python3 -m venv $Root/hf-venv
$Root/hf-venv/bin/pip install -q -U huggingface_hub
$Root/hf-venv/bin/hf download $ModelRepo $ModelFile --local-dir $Models
"@
    Invoke-WslBash "test -s $Models/$ModelFile"
}

Write-Host ''
Write-Host 'RTX 4080 NInfer backend installed.' -ForegroundColor Green
Write-Host "Engine: $Build/apps/ninfer-serve"
if ($Mode -eq 'BuildAndDownload') { Write-Host "Model:  $Models/$ModelFile" }
Write-Host 'Next: run .\Start-NInfer4080.ps1 and verify http://127.0.0.1:5100/v1/models.'
