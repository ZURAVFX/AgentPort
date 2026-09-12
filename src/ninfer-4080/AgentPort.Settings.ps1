$script:AgentPortSettingsScriptPath = Join-Path $PSScriptRoot 'AgentPort.Settings.js'

function Get-AgentPortSettingsNodePath {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($script:PortableNodeDir){[void]$candidates.Add((Join-Path ([string]$script:PortableNodeDir) 'node.exe'))}
    if($script:AppDataDir){[void]$candidates.Add((Join-Path ([string]$script:AppDataDir) 'node.exe'))}
    try{$command=Get-Command node.exe -ErrorAction Stop;if($command.Source){[void]$candidates.Add([string]$command.Source)}}catch{}
    if(@($candidates | Where-Object {Test-Path -LiteralPath $_}).Count -eq 0 -and (Get-Command Ensure-PortableNode -ErrorAction SilentlyContinue)){
        try { [void](Ensure-PortableNode) } catch {}
        if($script:PortableNodeDir){[void]$candidates.Add((Join-Path ([string]$script:PortableNodeDir) 'node.exe'))}
    }
    foreach($candidate in @($candidates | Select-Object -Unique)){if(Test-Path -LiteralPath $candidate){return $candidate}}
    throw 'The Node runtime needed to repair Harness settings is not available.'
}

function Add-AgentPortSettingsYamlCandidate([System.Collections.Generic.List[string]]$List,[string]$Root) {
    if([string]::IsNullOrWhiteSpace($Root)){return}
    $package=Join-Path $Root 'package.json'
    if((Split-Path -Leaf $Root) -eq 'yaml' -and (Test-Path -LiteralPath $package)){[void]$List.Add($Root);return}
    $direct=Join-Path $Root 'node_modules\yaml'
    if(Test-Path -LiteralPath (Join-Path $direct 'package.json')){[void]$List.Add($direct)}
    $pnpm=Join-Path $Root 'node_modules\.pnpm'
    if(Test-Path -LiteralPath $pnpm){
        Get-ChildItem -LiteralPath $pnpm -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $nested=Join-Path $_.FullName 'node_modules\yaml'
                if(Test-Path -LiteralPath (Join-Path $nested 'package.json')){[void]$List.Add($nested)}
            }
    }
}

function Get-AgentPortSettingsYamlRoot {
    $bundled=Join-Path $PSScriptRoot 'vendor\yaml'
    if(Test-Path -LiteralPath (Join-Path $bundled 'package.json')){return $bundled}
    $candidates=New-Object System.Collections.Generic.List[string]
    $harness=''
    if($script:Config -and $script:Config.PSObject.Properties.Name -contains 'harness_root'){$harness=[string]$script:Config.harness_root}
    if($harness){Add-AgentPortSettingsYamlCandidate $candidates $harness}
    if($script:HarnessRoot){Add-AgentPortSettingsYamlCandidate $candidates ([string]$script:HarnessRoot)}
    $configuredCache=''
    if($script:NpmCacheDir){$configuredCache=[string]$script:NpmCacheDir}
    if(-not $configuredCache -and $script:AppDataDir){$configuredCache=Join-Path ([string]$script:AppDataDir) 'npm-cache'}
    $cacheRoots=@($configuredCache,(Join-Path $env:LOCALAPPDATA 'AgentPort\npm-cache')) | Where-Object {[string]::IsNullOrWhiteSpace($_) -eq $false} | Select-Object -Unique
    foreach($cache in $cacheRoots){
        Add-AgentPortSettingsYamlCandidate $candidates $cache
        $npxRoot=Join-Path $cache '_npx'
        if(Test-Path -LiteralPath $npxRoot){
            Get-ChildItem -LiteralPath $npxRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {Add-AgentPortSettingsYamlCandidate $candidates $_.FullName}
        }
    }
    foreach($candidate in @($candidates | Select-Object -Unique)){
        if(Test-Path -LiteralPath (Join-Path $candidate 'package.json')){return $candidate}
    }
    throw 'The Harness YAML dependency could not be located in the configured runtime or npm cache.'
}

function Get-AgentPortSettingsRuntime {
    [pscustomobject]@{
        NodePath=(Get-AgentPortSettingsNodePath)
        ScriptPath=$script:AgentPortSettingsScriptPath
        YamlRoot=(Get-AgentPortSettingsYamlRoot)
    }
}

function Invoke-AgentPortYamlSettingsMutation {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$false)]$Operations=@(),
        [Parameter(Mandatory=$false)][string]$BackupPath=''
    )
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Harness settings path is empty.'}
    $runtime=Get-AgentPortSettingsRuntime
    $temp=[IO.Path]::Combine([IO.Path]::GetTempPath(),('agentport-settings-'+[IO.Path]::GetRandomFileName()+'.json'))
    $json=ConvertTo-Json $Operations -Depth 24 -Compress
    [IO.File]::WriteAllText($temp,$json,([Text.UTF8Encoding]::new($false)))
    try {
        $output=& $runtime.NodePath $runtime.ScriptPath '--apply' $Path $temp $BackupPath $runtime.YamlRoot 2>$null
        if($LASTEXITCODE -ne 0){throw 'The Harness settings YAML was invalid or contained an ambiguous duplicate.'}
        return ([string](@($output | Select-Object -Last 1)) -eq 'changed')
    } catch {
        if($_.Exception.Message -like 'The Harness settings YAML was invalid*'){throw $_}
        throw 'The Harness settings YAML operation could not be completed safely.'
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

function Repair-HarnessSettingsFile {
    $path=[string]$script:SettingsPath
    if([string]::IsNullOrWhiteSpace($path) -or -not(Test-Path -LiteralPath $path)){return $false}
    try {
        $backup=$path+'.before-agentport-settings-repair'
        $changed=Invoke-AgentPortYamlSettingsMutation -Path $path -Operations @([pscustomobject]@{kind='repair'}) -BackupPath $backup
        if($changed -and $null -ne $LogBox){Set-Log 'Repaired duplicate Harness settings maps. The original settings file was backed up.' 'ok'}
        return [bool]$changed
    } catch {
        if($null -ne $LogBox){Set-Log ('Could not repair Harness settings: '+$_.Exception.Message) 'error'}
        throw 'Harness settings could not be repaired safely.'
    }
}

function Set-AgentPortHarnessSettings {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Model,
        [Parameter(Mandatory=$true)][string]$DisplayName,
        [Parameter(Mandatory=$true)][int]$Context,
        [Parameter(Mandatory=$true)][int]$MaxTokens,
        [Parameter(Mandatory=$false)][bool]$Vision=$false
    )
    $inputModalities=if($Vision){@('text','image')}else{@('text')}
    $provider=[ordered]@{
        displayName='AgentPort Local'
        apiKeyEnv='TEXTGEN_API_KEY'
        api='openai-completions'
        baseURL='http://127.0.0.1:5100/v1'
        defaultInput=$inputModalities
        timeoutMs=3600000
        streamIdleTimeoutMs=3600000
        websocketConnectTimeoutMs=3600000
        retryPolicy=[ordered]@{mode='normal';maxRetries=0}
        models=@([ordered]@{id=$Model;name=$DisplayName;contextWindow=$Context;maxTokens=$MaxTokens;inputModalities=$inputModalities})
    }
    $operations=@(
        [pscustomobject]@{kind='ensure-provider';provider='agentport-local';value=$provider}
        [pscustomobject]@{kind='set-default-model';provider='agentport-local';model=$Model}
    )
    Invoke-AgentPortYamlSettingsMutation -Path $Path -Operations $operations -BackupPath ($Path+'.before-agentport-settings')
}

function Set-AgentPortNInferSettings {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][int]$Context,
        [Parameter(Mandatory=$false)][int]$MaxTokens=4096
    )
    $provider=[ordered]@{
        displayName='NInfer RTX 4080'
        apiKeyEnv='NINFER_API_KEY'
        api='openai-completions'
        baseURL='http://127.0.0.1:5100/v1'
        defaultInput=@('text')
        compat=[ordered]@{supportsDeveloperRole=$false;maxTokensField='max_tokens'}
        timeoutMs=3600000
        streamIdleTimeoutMs=3600000
        websocketConnectTimeoutMs=3600000
        retryPolicy=[ordered]@{mode='normal';maxRetries=0}
        models=@([ordered]@{id='qwen3.8-27b-minq4';name='Qwen3.8 27B min-Q4 (NInfer MTP3)';contextWindow=$Context;maxTokens=$MaxTokens})
    }
    $operations=@(
        [pscustomobject]@{kind='ensure-provider';provider='ninfer-local';value=$provider}
        [pscustomobject]@{kind='set-default-model';provider='ninfer-local';model='qwen3.8-27b-minq4'}
    )
    Invoke-AgentPortYamlSettingsMutation -Path $Path -Operations $operations -BackupPath ($Path+'.before-agentport-settings')
}

function Set-AgentPortPresetDefault {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Preset,
        [Parameter(Mandatory=$false)][string]$BackupSuffix='.before-agentport-preset'
    )
    Invoke-AgentPortYamlSettingsMutation -Path $Path -Operations @([pscustomobject]@{kind='set-preset-default';preset=$Preset}) -BackupPath ($Path+$BackupSuffix)
}
