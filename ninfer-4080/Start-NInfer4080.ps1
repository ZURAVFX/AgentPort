[CmdletBinding()]
param([string]$Distro='Ubuntu-24.04',[ValidateSet('Safe','Balanced','Long')][string]$Profile='Balanced',[int]$Port=5100)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
$contexts=@{Safe=8192;Balanced=24576;Long=32768}
$service=$null
try {
    $service=Start-NInferService -Distro $Distro -Context $contexts[$Profile] -Port $Port
    Write-Host 'NInfer is running. Keep this window open; Ctrl+C stops this instance.'
    Wait-Process -Id $service.Process.Id
} finally {if($service){Stop-NInferService $service}}
