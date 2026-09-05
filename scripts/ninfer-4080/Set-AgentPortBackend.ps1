[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Auto','NInfer4080','TextGen')]
    [string]$Backend,
    [string]$Distro = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'
$configDir = Join-Path $env:USERPROFILE '.dsh'
$configFile = Join-Path $configDir 'launcher_config.json'
if(-not (Test-Path $configDir)){ New-Item -ItemType Directory -Force -Path $configDir | Out-Null }

if(Test-Path $configFile){
    $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
}else{
    $cfg = [pscustomobject]@{}
}

if($cfg.PSObject.Properties.Name -contains 'runtime_backend'){
    $cfg.runtime_backend = $Backend
}else{
    $cfg | Add-Member -NotePropertyName runtime_backend -NotePropertyValue $Backend
}
if($cfg.PSObject.Properties.Name -contains 'ninfer_wsl_distro'){
    $cfg.ninfer_wsl_distro = $Distro
}else{
    $cfg | Add-Member -NotePropertyName ninfer_wsl_distro -NotePropertyValue $Distro
}

$cfg | ConvertTo-Json -Depth 12 | Set-Content -Path $configFile -Encoding UTF8
Write-Host "AgentPort runtime backend set to: $Backend" -ForegroundColor Green
Write-Host "Config: $configFile"
if($Backend -eq 'Auto'){
    Write-Host 'Auto uses NInfer for Qwen3.8-27B-Ridge-3.7bpw when the RTX 4080 WSL backend is installed; otherwise it falls back to TextGen.'
}elseif($Backend -eq 'NInfer4080'){
    Write-Host 'NInfer4080 requests the optimized backend. If its prerequisites are missing, AgentPort logs a warning and falls back to TextGen.'
}else{
    Write-Host 'TextGen forces the existing GGUF backend.'
}
