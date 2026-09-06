param([string]$HarnessRoot='')
$ErrorActionPreference='Stop'
if(-not $HarnessRoot){$HarnessRoot=[string](Get-Content (Join-Path $env:USERPROFILE '.dsh\launcher_config.json') -Raw | ConvertFrom-Json).harness_root}
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')
$testDir=Join-Path $PSScriptRoot 'results\harness'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
$testDir=(Resolve-Path $testDir).Path
# Exercise AgentPort's actual settings writer without changing the user's settings.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\AgentPort-runtime-v1.7.0-4080.ps1'),[ref]$null,[ref]$null)
$writer=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Update-HarnessSettings'},$true)
Invoke-Expression $writer.Extent.Text
function Ensure-ConfigDir {}
$script:SettingsPath=Join-Path $testDir 'settings.yaml'
Update-HarnessSettings 'qwen3.8-27b-minq4' 'Qwen3.8 27B min-Q4 (NInfer)' 24576 1024
$patch=Join-Path $testDir 'patch.yml'
$null=New-NInferHarnessPatch $patch $script:SettingsPath
$state=$null
try {
    $state=Start-NInferService -Port 5100 -LogDirectory $testDir
    $env:TEXTGEN_API_KEY='local-textgen'
    Push-Location $HarnessRoot
    try {
        & corepack pnpm dsh --profile headless --patch $patch 'Use your shell tool to calculate 17 * 19. Then reply with the result only. Do not edit any files.'
        if($LASTEXITCODE -ne 0){throw "Harness exited $LASTEXITCODE"}
    } finally {Pop-Location}
} finally {if($state){Stop-NInferService $state}}
