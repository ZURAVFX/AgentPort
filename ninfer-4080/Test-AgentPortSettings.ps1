$ErrorActionPreference='Stop'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('agentport-settings-'+[guid]::NewGuid().ToString('N'))

function Assert-AgentPortSettings([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-AgentPortSettingsFixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,([Text.UTF8Encoding]::new($false)))}

try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $script:AppDataDir=Join-Path $scratch 'appdata'
    $script:PortableNodeDir=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AgentPort\node-v22.23.1-win-x64'
    $script:NpmCacheDir=Join-Path $env:LOCALAPPDATA 'AgentPort\npm-cache'
    $script:Config=[pscustomobject]@{harness_root=(Join-Path $scratch 'harness')}
    . (Join-Path $PSScriptRoot 'AgentPort.Settings.ps1')

    foreach($seed in @('', '"llm-pi-ai": { providers: {} }', "llm-pi-ai:`n  providers:`n")){
        $fresh=Join-Path $scratch ('fresh-'+[guid]::NewGuid().ToString('N')+'.yaml')
        if($seed){Write-AgentPortSettingsFixture $fresh $seed}
        [void](Set-AgentPortHarnessSettings -Path $fresh -Model 'same-model' -DisplayName 'Same Model' -Context 65536 -MaxTokens 2048)
        $first=[IO.File]::ReadAllText($fresh)
        [void](Set-AgentPortHarnessSettings -Path $fresh -Model 'same-model' -DisplayName 'Same Model' -Context 65536 -MaxTokens 2048)
        Assert-AgentPortSettings ($first -ceq [IO.File]::ReadAllText($fresh)) 'repeated model selection changed settings'
        Assert-AgentPortSettings ([regex]::Matches($first,'(?m)^llm-pi-ai:').Count -eq 1) 'fresh or inline-empty providers created duplicate settings'
    }

    $settings=Join-Path $scratch 'settings.yaml'
    $backup=$settings+'.before-agentport-settings'
    Write-AgentPortSettingsFixture $settings @'
llm-pi-ai: { providers: { inline: { displayName: Inline } }, keep: first }
llm-pi-ai:
  providers:
    existing:
      displayName: Existing
agent-presets:
  default: first-default
agent-presets:
  default: second-default
textgen-local:
  models:
    - id: preserve-me
'@
    [void](Set-AgentPortHarnessSettings -Path $settings -Model 'model-a' -DisplayName 'Model A' -Context 49152 -MaxTokens 4096)
    $text=[IO.File]::ReadAllText($settings)
    Assert-AgentPortSettings (@([regex]::Matches($text,'(?m)^llm-pi-ai:')).Count -eq 1) 'duplicate llm-pi-ai map was not normalised'
    Assert-AgentPortSettings (@([regex]::Matches($text,'(?m)^agent-presets:')).Count -eq 1) 'duplicate agent-presets map was not normalised'
    Assert-AgentPortSettings ($text -match '(?m)^    inline:') 'inline provider was lost'
    Assert-AgentPortSettings ($text -match '(?m)^    existing:') 'sibling provider was lost'
    Assert-AgentPortSettings ($text -match '(?m)^    agentport-local:') 'AgentPort provider was not written'
    Assert-AgentPortSettings ($text -match 'first-default') 'first duplicate preset value was not retained'
    Assert-AgentPortSettings ($text -match 'preserve-me') 'unrelated provider content was lost'
    Assert-AgentPortSettings (Test-Path -LiteralPath $backup) 'valid mutation did not create a backup'

    [void](Set-AgentPortNInferSettings -Path $settings -Context 24576 -MaxTokens 4096)
    $text=[IO.File]::ReadAllText($settings)
    Assert-AgentPortSettings ($text -match '(?m)^    ninfer-local:') 'NInfer provider was not written'
    Assert-AgentPortSettings ($text -match '(?m)^  provider: ninfer-local') 'NInfer default model was not written'
    Assert-AgentPortSettings ($text -match 'preserve-me') 'NInfer update removed an unrelated provider'

    $presetBefore=[IO.File]::ReadAllText($settings)
    [void](Set-AgentPortPresetDefault -Path $settings -Preset 'zura-low-thinking' -BackupSuffix '.before-zura-test')
    $presetAfter=[IO.File]::ReadAllText($settings)
    Assert-AgentPortSettings ($presetAfter -match '(?m)^  default: zura-low-thinking$') 'preset default was not updated structurally'
    [void](Set-AgentPortPresetDefault -Path $settings -Preset 'zura-low-thinking' -BackupSuffix '.before-zura-test')
    Assert-AgentPortSettings ($presetAfter -ceq [IO.File]::ReadAllText($settings)) 'preset update was not idempotent'

    $invalid=Join-Path $scratch 'invalid.yaml'
    $invalidText="llm-pi-ai:`n  providers: [`n"
    Write-AgentPortSettingsFixture $invalid $invalidText
    $invalidBytes=[IO.File]::ReadAllBytes($invalid)
    $failed=$false
    try {[void](Invoke-AgentPortYamlSettingsMutation -Path $invalid -Operations @([pscustomobject]@{kind='repair'}) -BackupPath ($invalid+'.before'))} catch {$failed=$true}
    Assert-AgentPortSettings $failed 'invalid YAML was accepted'
    Assert-AgentPortSettings (([Convert]::ToBase64String($invalidBytes)) -ceq ([Convert]::ToBase64String([IO.File]::ReadAllBytes($invalid)))) 'invalid YAML was mutated'
    Assert-AgentPortSettings (-not(Test-Path -LiteralPath ($invalid+'.before'))) 'invalid YAML created a backup despite no mutation'

    $ambiguous=Join-Path $scratch 'ambiguous.yaml'
    $ambiguousText="conflict: one`nconflict: two`n"
    Write-AgentPortSettingsFixture $ambiguous $ambiguousText
    $failed=$false
    try {[void](Invoke-AgentPortYamlSettingsMutation -Path $ambiguous -Operations @([pscustomobject]@{kind='repair'}) -BackupPath ($ambiguous+'.before'))} catch {$failed=$true}
    Assert-AgentPortSettings $failed 'ambiguous scalar duplicate was accepted'
    Assert-AgentPortSettings ($ambiguousText -ceq [IO.File]::ReadAllText($ambiguous)) 'ambiguous scalar duplicate was mutated'

    Write-Host 'AgentPort settings tests passed.'
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'agentport-settings-*'){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
