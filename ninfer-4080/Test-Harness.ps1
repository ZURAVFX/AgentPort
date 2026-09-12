param([string]$HarnessRoot='')
$ErrorActionPreference='Stop'
if(-not $HarnessRoot){$HarnessRoot=[string](Get-Content (Join-Path $env:USERPROFILE '.dsh\launcher_config.json') -Raw | ConvertFrom-Json).harness_root}
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Settings.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Presets.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Team.ps1')
$testDir=Join-Path $PSScriptRoot 'results\harness'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
$testDir=(Resolve-Path $testDir).Path
# Exercise AgentPort's actual NInfer provider writer without changing the user's settings.
function Ensure-ConfigDir {}
$script:SettingsPath=Join-Path $testDir 'settings.yaml'
$script:Config=@{harness_root=$HarnessRoot;harness_skills_root=(Join-Path $env:USERPROFILE '.dsh\harness_skills')}
Remove-Item -LiteralPath $script:SettingsPath -Force -ErrorAction SilentlyContinue
Update-NInferHarnessSettings 24576 1024
Install-AgentPortTeamPreset
$patch=Join-Path $testDir 'patch.yml'
$null=New-NInferHarnessPatch $patch $script:SettingsPath
$state=$null
try {
    $state=Start-NInferService -Port 5100 -LogDirectory $testDir
    $env:NINFER_API_KEY='local-textgen'
    Push-Location $HarnessRoot
    try {
        & corepack pnpm dsh --profile headless --patch $patch 'Use your shell tool to calculate 17 * 19. Then reply with the result only. Do not edit any files.'
        if($LASTEXITCODE -ne 0){throw "Harness exited $LASTEXITCODE"}
    } finally {Pop-Location}
} finally {if($state){Stop-NInferService $state}}
