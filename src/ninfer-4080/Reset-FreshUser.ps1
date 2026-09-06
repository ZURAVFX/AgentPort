param([switch]$Apply)
$ErrorActionPreference='Stop'
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$backup=Join-Path $env:LOCALAPPDATA "AgentPort\backups\fresh-user-$stamp"
$targets=@()
$textgenPresets='C:\AI\textgen\user_data\presets'
if(Test-Path $textgenPresets){
    $targets+=Get-ChildItem -LiteralPath $textgenPresets -File -ErrorAction SilentlyContinue
}
$presetRoot=Join-Path $env:USERPROFILE '.dsh\.agent-presets'
foreach($name in @('agentport-team','agentport-fast','customzura','zura-low-thinking')){
    $path=Join-Path $presetRoot $name
    if(Test-Path $path){$targets+=Get-Item -LiteralPath $path}
}
$config=Join-Path $env:USERPROFILE '.dsh\launcher_config.json'
$settings=Join-Path $env:USERPROFILE '.dsh\settings.yaml'
$profiles=Join-Path $env:USERPROFILE '.dsh\agentport_profiles.json'
if(-not $Apply){
    [pscustomobject]@{Backup=$backup;Move=@($targets.FullName);Reset=@($config,$settings,$profiles);Preserved=(Join-Path $env:USERPROFILE '.dsh\agentport-mcp.json')} | ConvertTo-Json -Depth 4
    return
}
New-Item -ItemType Directory -Force -Path $backup | Out-Null
if(Test-Path $settings){Copy-Item -LiteralPath $settings -Destination (Join-Path $backup 'settings.yaml')}
if(Test-Path $config){Copy-Item -LiteralPath $config -Destination (Join-Path $backup 'launcher_config.json')}
if(Test-Path $profiles){Move-Item -LiteralPath $profiles -Destination (Join-Path $backup 'agentport_profiles.json')}
foreach($target in $targets){
    $group=if($target.FullName.StartsWith($textgenPresets,[StringComparison]::OrdinalIgnoreCase)){'textgen-presets'}else{'agent-presets'}
    $destination=Join-Path $backup $group
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Move-Item -LiteralPath $target.FullName -Destination (Join-Path $destination $target.Name)
}
if(Test-Path $config){
    $value=Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
    $value.last_model='';$value.active_model='';$value.active_context_tokens=0;$value.active_offload_mode=''
    $value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $config -Encoding utf8
}
if(Test-Path $settings){
    $text=[IO.File]::ReadAllText($settings)
    foreach($provider in @('ninfer-local','textgen-local','agentport-local')){
        $text=[regex]::Replace($text,"(?ms)^    $([regex]::Escape($provider)):\s*\r?\n.*?(?=^    \S|^\S|\z)",'')
    }
    foreach($section in @('agent-default-model','agent-presets','subagent-model-selection')){
        $text=[regex]::Replace($text,"(?ms)^$([regex]::Escape($section)):\s*\r?\n.*?(?=^\S|\z)",'')
    }
    [IO.File]::WriteAllText($settings,$text.TrimEnd()+"`r`n",[Text.UTF8Encoding]::new($false))
}
Write-Host "Fresh-user state prepared. Backup: $backup"
Write-Host 'Models, MCP configuration, credentials, ComfyUI and Blender data were preserved.'
