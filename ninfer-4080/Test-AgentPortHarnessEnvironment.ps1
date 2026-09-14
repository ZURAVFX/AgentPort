param([string]$RuntimePath=(Join-Path $PSScriptRoot '..\AgentPort-runtime-v1.7.0-4080.ps1'))
$ErrorActionPreference='Stop'
$tokens=$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $RuntimePath),[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors.Message -join '; ')}
$startDefinitions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-Harness'},$false))
if($startDefinitions.Count -ne 1){throw 'Production Start-Harness definition not found exactly once.'}
Invoke-Expression $startDefinitions[0].Extent.Text
function Assert-Test($condition,[string]$message){if(-not $condition){throw $message}}
function Test-Port([int]$Port){return $false}
function Ensure-AgentPortRuntimeDirs {}
function Repair-HarnessSettingsFile {return $false}
function Repair-AgentPortPresetCompatibility {}
function Ensure-AgentPortSkillIsolation {}
function Prepare-IsolatedHarnessSkills {}
function Ensure-PortableNode {return (Join-Path $script:TestRoot 'node.exe')}
function Write-AgentPortMcpOverlay {param($Path);return $null}
function Get-AgentPortProcessRecord {param($Id,$Process);return [pscustomobject]@{Id=$Id}}
function Start-Process {
    param([string]$FilePath,[object[]]$ArgumentList,[string]$WorkingDirectory,[object]$WindowStyle,[switch]$PassThru,[string]$RedirectStandardOutput,[string]$RedirectStandardError)
    $script:StartProcessCount++
    $script:ObservedBaseUrl=[Environment]::GetEnvironmentVariable('DEEPSEEK_BASE_URL',[EnvironmentVariableTarget]::Process)
    return [pscustomobject]@{Id=4242}
}
function Get-ProcessBaseUrl {
    $envs=[Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::Process)
    [pscustomobject]@{Present=$envs.Contains('DEEPSEEK_BASE_URL');Value=[string]$envs['DEEPSEEK_BASE_URL']}
}
function Set-ProcessBaseUrl([bool]$Present,[string]$Value){if($Present){$env:DEEPSEEK_BASE_URL=$Value}else{Remove-Item Env:DEEPSEEK_BASE_URL -ErrorAction SilentlyContinue}}
$originalEnv=Get-ProcessBaseUrl
$script:TestRoot=Join-Path ([IO.Path]::GetTempPath()) ('AgentPort-HarnessEnvTest-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $script:TestRoot | Out-Null
$script:AppDataDir=$script:TestRoot;$script:NpmCacheDir=$script:TestRoot;$script:PortableNodeDir=$script:TestRoot
$script:PendingModel='fixture-model.gguf';$script:PendingContext=49152
$script:StopOperation=[pscustomobject]@{Active=$false;Generation=0}
$script:HarnessOwnership=$null;$script:HarnessProcess=$null
$script:Config=@{harness_root=$script:TestRoot;team_workspace=$script:TestRoot;harness_runtime='npx-latest';harness_base_url='https://configured.example.test/v1'}
try {
    Set-ProcessBaseUrl $false ''
    $script:StartProcessCount=0;Start-Harness
    $state=Get-ProcessBaseUrl
    Assert-Test ($script:ObservedBaseUrl -eq 'https://configured.example.test/v1' -and -not $state.Present -and $script:StartProcessCount -eq 1) 'Configured base URL was not inherited and restored after success.'

    Set-ProcessBaseUrl $true 'https://existing.example.test'
    $script:Config.harness_base_url='http://configured.example.test/api';$script:StartProcessCount=0;Start-Harness
    $state=Get-ProcessBaseUrl
    Assert-Test ($script:ObservedBaseUrl -eq 'http://configured.example.test/api' -and $state.Present -and $state.Value -eq 'https://existing.example.test') 'Existing base URL was not restored after success.'

    $script:Config.harness_base_url='https://user:pass@example.test'
    $threw=$false;try{Start-Harness}catch{$threw=$true}
    $state=Get-ProcessBaseUrl
    Assert-Test ($threw -and $state.Present -and $state.Value -eq 'https://existing.example.test') 'Base URL was not restored after validation throw.'

    $script:Config.harness_base_url='';$script:StartProcessCount=0;Start-Harness
    $state=Get-ProcessBaseUrl
    Assert-Test ($script:ObservedBaseUrl -eq 'https://existing.example.test' -and $state.Present -and $state.Value -eq 'https://existing.example.test' -and $script:StartProcessCount -eq 1) 'Empty config did not preserve the existing process environment.'
    Write-Host 'PASS: Start-Harness base URL validation, child inheritance, success/throw restoration, and empty-config preservation.'
} finally {
    Set-ProcessBaseUrl $originalEnv.Present $originalEnv.Value
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
