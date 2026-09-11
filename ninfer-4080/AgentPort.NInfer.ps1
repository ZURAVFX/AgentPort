# NInfer is selected as its own model in AgentPort's existing model selector.
#
# Stop ownership is intentionally conservative. A listening port is only a
# lookup hint: it never grants permission to terminate a process. Every target
# below carries PID, creation time, executable path and command line captured
# before the stop starts. The same fields must still match immediately before
# termination, which prevents PID reuse from killing a newer unrelated process.

function ConvertTo-AgentPortStopPath {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return ''}
    try{return [IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()}catch{return $Path.TrimEnd('\').ToLowerInvariant()}
}

function ConvertTo-AgentPortCreationTime {
    param($Value)
    if($null -eq $Value){return $null}
    try {
        if($Value -is [datetime]){return ([datetime]$Value).ToUniversalTime()}
        return [Management.ManagementDateTimeConverter]::ToDateTime([string]$Value).ToUniversalTime()
    } catch { try{return ([datetime]$Value).ToUniversalTime()}catch{return $null} }
}

function Get-AgentPortProcessRecord {
    param([int]$ProcessId,[object]$Process)
    if($ProcessId -le 0 -and $Process){$ProcessId=[int]$Process.Id}
    if($ProcessId -le 0){return $null}
    try{$cim=Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop}catch{return $null}
    if(-not $cim){return $null}
    $start=ConvertTo-AgentPortCreationTime $cim.CreationDate
    if(-not $start -and $Process){try{$start=([datetime]$Process.StartTime).ToUniversalTime()}catch{}}
    [pscustomobject]@{
        Pid=[int]$cim.ProcessId; ParentPid=[int]$cim.ParentProcessId; StartTime=$start
        ExecutablePath=[string]$cim.ExecutablePath; CommandLine=[string]$cim.CommandLine
        Depth=0
    }
}

function Get-AgentPortProcessRecords {
    param([object[]]$Records)
    if($null -ne $Records){return @($Records|ForEach-Object{[pscustomobject]$_})}
    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Pid=[int]$_.ProcessId;ParentPid=[int]$_.ParentProcessId;StartTime=(ConvertTo-AgentPortCreationTime $_.CreationDate)
                ExecutablePath=[string]$_.ExecutablePath;CommandLine=[string]$_.CommandLine;Depth=0
            }
        })
    } catch {return @()}
}

function Test-AgentPortProcessIdentity {
    param([Parameter(Mandatory)]$Expected,[object[]]$Records)
    if(-not $Expected -or [int]$Expected.Pid -le 0){return $false}
    $current=$null
    if($Records){$current=@($Records|Where-Object{[int]$_.Pid -eq [int]$Expected.Pid}|Select-Object -First 1)}
    if($current -is [array]){$current=$current|Select-Object -First 1}
    if(-not $current){$current=Get-AgentPortProcessRecord ([int]$Expected.Pid)}
    if(-not $current){return $false}
    $expectedStart=ConvertTo-AgentPortCreationTime $Expected.StartTime
    $currentStart=ConvertTo-AgentPortCreationTime $current.StartTime
    if(-not $expectedStart -or -not $currentStart -or $expectedStart.Ticks -ne $currentStart.Ticks){return $false}
    if((ConvertTo-AgentPortStopPath ([string]$Expected.ExecutablePath)) -ne (ConvertTo-AgentPortStopPath ([string]$current.ExecutablePath))){return $false}
    if([string]$Expected.CommandLine -ne [string]$current.CommandLine){return $false}
    return $true
}

function Get-AgentPortProcessDescendants {
    param([Parameter(Mandatory)]$Root,[Parameter(Mandatory)][object[]]$Records)
    $result=New-Object System.Collections.Generic.List[object]
    $queue=New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{Record=$Root;Depth=0})
    while($queue.Count -gt 0){
        $item=$queue.Dequeue()
        foreach($child in @($Records|Where-Object{[int]$_.ParentPid -eq [int]$item.Record.Pid})){
            if([int]$child.Pid -eq [int]$Root.Pid -or @($result|Where-Object{[int]$_.Pid -eq [int]$child.Pid}).Count -gt 0){continue}
            $copy=[pscustomobject]@{Pid=[int]$child.Pid;ParentPid=[int]$child.ParentPid;StartTime=$child.StartTime;ExecutablePath=[string]$child.ExecutablePath;CommandLine=[string]$child.CommandLine;Depth=([int]$item.Depth+1)}
            [void]$result.Add($copy);$queue.Enqueue([pscustomobject]@{Record=$copy;Depth=$copy.Depth})
        }
    }
    return $result.ToArray()
}

function Get-AgentPortHarnessCachedEntries {
    param([string]$NpmCacheRoot)
    $entries=New-Object System.Collections.Generic.List[string]
    if(-not $NpmCacheRoot -or -not (Test-Path -LiteralPath $NpmCacheRoot)){return @()}
    try {
        Get-ChildItem -LiteralPath (Join-Path $NpmCacheRoot '_npx') -Filter package.json -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {$_.FullName -match '(?i)node_modules\\@deepseek-ai\\dsh\\package\.json'} |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                $entry=Join-Path $_.Directory.FullName 'lib\bin.js'
                if(Test-Path -LiteralPath $entry){[void]$entries.Add((ConvertTo-AgentPortStopPath $entry))}
            }
    } catch {}
    return @($entries.ToArray()|Select-Object -Unique)
}

function Test-AgentPortHarnessCachedRecord {
    param([Parameter(Mandatory)]$Record,[string[]]$CachedEntries,[string]$PortableNodeDir)
    $exe=ConvertTo-AgentPortStopPath ([string]$Record.ExecutablePath)
    # npx may resolve the cached entry through the portable runtime, an
    # existing system Node install, or nvm. The executable identity therefore
    # requires a real node.exe, while ownership is proven by the exact cached
    # AgentPort dsh lib/bin.js path below. This keeps unrelated Node apps out.
    if(-not $exe -or ([IO.Path]::GetFileName($exe) -notmatch '^(?i)node\.exe$')){return $false}
    $command=([string]$Record.CommandLine).Replace('/','\')
    if($command -notmatch '(?i)(^|\s|["''])web(["'']|\s|$)'){return $false}
    foreach($entry in @($CachedEntries)){
        $needle=[string]$entry
        if($needle -and (ConvertTo-AgentPortStopPath $command).Contains($needle)){return $true}
    }
    return $false
}

function Test-AgentPortHarnessWrapperRecord {
    param([Parameter(Mandatory)]$Record,[string]$HarnessRoot,[string]$NpmCacheRoot)
    $command=[string]$Record.CommandLine
    if([string]::IsNullOrWhiteSpace($command)){return $false}
    $hasWeb=$command -match '(?i)(^|\s|["''])web(["'']|\s|$)'
    $hasCache=($NpmCacheRoot -and (ConvertTo-AgentPortStopPath $command).Contains((ConvertTo-AgentPortStopPath $NpmCacheRoot)))
    $hasRoot=($HarnessRoot -and (ConvertTo-AgentPortStopPath $command).Contains((ConvertTo-AgentPortStopPath $HarnessRoot)))
    return [bool]($hasWeb -and ($hasCache -or $hasRoot) -and ($command -match '(?i)(npx|dsh|node|cmd)'))
}

function Test-AgentPortBackendRecord {
    param([Parameter(Mandatory)]$Record,[string]$TextGenRoot,[string]$ManagedRuntimeRoot)
    $command=[string]$Record.CommandLine
    $exe=ConvertTo-AgentPortStopPath ([string]$Record.ExecutablePath)
    if($command -match '(?i)server\.py' -and $TextGenRoot -and $exe.StartsWith((ConvertTo-AgentPortStopPath $TextGenRoot))){return $true}
    if($command -match '(?i)llama-server' -and $ManagedRuntimeRoot -and ($exe.StartsWith((ConvertTo-AgentPortStopPath $ManagedRuntimeRoot)) -or $command.ToLowerInvariant().Contains((ConvertTo-AgentPortStopPath $ManagedRuntimeRoot)))){return $true}
    return $false
}

function Get-AgentPortStopPlan {
    param(
        [Parameter(Mandatory)][ValidateSet('backend','harness')][string]$Kind,
        [Parameter(Mandatory)][int]$Port,
        [object]$OwnedProcess,
        [object[]]$ProcessRecords,
        [int[]]$ListenerPids,
        [string]$HarnessRoot,
        [string]$NpmCacheRoot,
        [string]$PortableNodeDir,
        [string]$TextGenRoot,
        [string]$ManagedRuntimeRoot
    )
    $records=Get-AgentPortProcessRecords $ProcessRecords
    $owned=$null
    $ownerExpected=$null
    if($OwnedProcess){
        if($OwnedProcess.Pid -and $OwnedProcess.StartTime -and $OwnedProcess.CommandLine -and $OwnedProcess.ExecutablePath){
            $ownerExpected=[pscustomobject]@{Pid=[int]$OwnedProcess.Pid;ParentPid=[int]$OwnedProcess.ParentPid;StartTime=$OwnedProcess.StartTime;ExecutablePath=[string]$OwnedProcess.ExecutablePath;CommandLine=[string]$OwnedProcess.CommandLine;Depth=0}
        } elseif($OwnedProcess.Id){$ownerExpected=Get-AgentPortProcessRecord ([int]$OwnedProcess.Id) $OwnedProcess}
        if($ownerExpected){
            $freshOwner=@($records|Where-Object{[int]$_.Pid -eq [int]$ownerExpected.Pid}|Select-Object -First 1)
            if($freshOwner -is [array]){$freshOwner=$freshOwner|Select-Object -First 1}
            if($freshOwner -and (Test-AgentPortProcessIdentity $ownerExpected $freshOwner)){$owned=$freshOwner}
        }
    }
    $targets=New-Object System.Collections.Generic.List[object]
    $cached=if($Kind -eq 'harness'){@(Get-AgentPortHarnessCachedEntries $NpmCacheRoot)}else{@()}
    if($owned -and (Test-AgentPortProcessIdentity $owned $records)){
        [void]$targets.Add($owned)
        $descendants=Get-AgentPortProcessDescendants $owned $records
        foreach($child in $descendants){
            $valid=if($Kind -eq 'harness'){(Test-AgentPortHarnessCachedRecord $child $cached $PortableNodeDir) -or (Test-AgentPortHarnessWrapperRecord $child $HarnessRoot $NpmCacheRoot)}else{Test-AgentPortBackendRecord $child $TextGenRoot $ManagedRuntimeRoot}
            if($valid){[void]$targets.Add($child)}
        }
    }
    $listeners=if($null -ne $ListenerPids){@($ListenerPids)}else{@(& netstat.exe -ano -p TCP 2>$null | ForEach-Object {if($_ -match ('^\s*TCP\s+\S+:'+([regex]::Escape([string]$Port))+ '\s+\S+\s+LISTENING\s+(\d+)\s*$')){[int]$Matches[1]}}|Select-Object -Unique)}
    foreach($listenerPid in $listeners){
        $candidate=@($records|Where-Object{[int]$_.Pid -eq [int]$listenerPid}|Select-Object -First 1)
        if($candidate -is [array]){$candidate=$candidate|Select-Object -First 1}
        if(-not $candidate){continue}
        $already=@($targets|Where-Object{[int]$_.Pid -eq [int]$candidate.Pid}).Count -gt 0
        if($already){continue}
        # An orphan is only eligible when its executable and exact cached entry
        # prove ownership. The listener PID by itself is never sufficient.
        $valid=if($Kind -eq 'harness'){Test-AgentPortHarnessCachedRecord $candidate $cached $PortableNodeDir}else{Test-AgentPortBackendRecord $candidate $TextGenRoot $ManagedRuntimeRoot}
        if($valid -and (Test-AgentPortProcessIdentity $candidate $records)){[void]$targets.Add($candidate)}
    }
    $targetArray=@($targets.ToArray()|Sort-Object @{Expression={$_.Depth};Descending=$true},Pid)
    return [pscustomobject]@{Kind=$Kind;Port=$Port;Processes=$targetArray;ListenerPids=@($listeners);UnownedListenerPids=@($listeners|Where-Object{[int]$_ -notin @($targetArray|ForEach-Object{$_.Pid})})}
}

function Stop-AgentPortProcess {
    param($Process,[object]$ExpectedRecord)
    if(-not $Process -and -not $ExpectedRecord){return $false}
    $expected=if($ExpectedRecord){$ExpectedRecord}else{Get-AgentPortProcessRecord ([int]$Process.Id) $Process}
    if(-not $expected){return $false}
    if(-not (Test-AgentPortProcessIdentity $expected)){return $false}
    try {
        Stop-Process -Id ([int]$expected.Pid) -Force -ErrorAction Stop
        try{Wait-Process -Id ([int]$expected.Pid) -Timeout 5 -ErrorAction SilentlyContinue}catch{}
        return $true
    } catch {return $false}
}

function Stop-AgentPortStopPlan {
    param([Parameter(Mandatory)]$Plan)
    $stopped=New-Object System.Collections.Generic.List[int]
    foreach($record in @($Plan.Processes)){
        if(Stop-AgentPortProcess $null $record){[void]$stopped.Add([int]$record.Pid)}
    }
    return [pscustomobject]@{StoppedPids=@($stopped.ToArray());UnownedListenerPids=@($Plan.UnownedListenerPids)}
}

function Stop-VerifiedAgentPortProcess {
    param([int]$Port,[ValidateSet('backend','harness')][string]$Kind)
    $harnessRoot=if($script:Config){[string]$script:Config.harness_root}else{''}
    $textgenRoot=if($script:Config){[string]$script:Config.textgen_root}else{''}
    $npm=if($script:NpmCacheDir){[string]$script:NpmCacheDir}else{Join-Path $env:LOCALAPPDATA 'AgentPort\npm-cache'}
    $node=if($script:PortableNodeDir){[string]$script:PortableNodeDir}else{Join-Path $env:LOCALAPPDATA 'AgentPort\node-v22.23.1-win-x64'}
    $plan=Get-AgentPortStopPlan -Kind $Kind -Port $Port -HarnessRoot $harnessRoot -NpmCacheRoot $npm -PortableNodeDir $node -TextGenRoot $textgenRoot -ManagedRuntimeRoot (Join-Path $env:LOCALAPPDATA 'AgentPort\llama-b10809')
    return Stop-AgentPortStopPlan $plan
}

function Stop-StaleNInferInstances {
    $temp=Join-Path $env:LOCALAPPDATA 'AgentPort/ninfer-stop'
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $distro=Get-AgentPortNInferDistro
    $linuxHome=((& wsl.exe -d $distro --exec printenv HOME) -join '').Trim()
    if($linuxHome -notmatch '^/[A-Za-z0-9._/-]+$'){return}
    # AgentPort has used more than one build directory over its iterations. Match
    # only ninfer-serve binaries inside AgentPort's own source tree so cleanup
    # cannot terminate an unrelated system or user-managed NInfer process.
    $root="$linuxHome/.agentport"
    $command=@'
set -eu
root='__ROOT__'
is_agentport_ninfer() {
  exe=$(readlink /proc/$1/exe 2>/dev/null || true)
  case "$exe" in
    "$root"/ninfer-src/ninfer-serve|"$root"/ninfer-src/*/ninfer-serve) return 0;;
    *) return 1;;
  esac
}
stop_if_owned() {
  target="$1"
  case "$target" in ''|*[!0-9]*) return;; esac
  if is_agentport_ninfer "$target"; then kill -TERM "$target" 2>/dev/null || true; fi
}
for file in "$root"/logs/agentport-*.pid "$root"/logs/agentport.pid; do
  test -f "$file" || continue
  read -r target < "$file"
  stop_if_owned "$target"
  rm -f "$file"
done
# Recover older AgentPort launches that predate PID files. The executable path
# guard above keeps this limited to binaries under ~/.agentport/ninfer-src.
for proc in /proc/[0-9]*; do
  target=${proc##*/}
  if is_agentport_ninfer "$target"; then stop_if_owned "$target"; fi
done
'@
    try {Invoke-NInferShell $distro ($command.Replace('__ROOT__',$root)) $temp | Out-Null}catch{}
}

function Test-AgentPortNInferInstalled {
    try {
        $distro=Get-AgentPortNInferDistro
        $linuxHome=((& wsl.exe -d $distro --exec printenv HOME) -join '').Trim()
        if($linuxHome -notmatch '^/[A-Za-z0-9._/-]+$'){return $false}
        & wsl.exe -d $distro --exec test -x "$linuxHome/.agentport/ninfer-src/build-sm89/apps/ninfer-serve"
        if($LASTEXITCODE -ne 0){return $false}
        & wsl.exe -d $distro --exec test -s "$linuxHome/.agentport/models/qwen3_8_27b_minq4.ninfer"
        return ($LASTEXITCODE -eq 0)
    } catch {return $false}
}

function Refresh-NInferControls {
    $installed=Test-AgentPortNInferInstalled
    if($ModelsNInferStatus){
        $ModelsNInferStatus.Text=if($installed){'Installed and ready'}else{'One-time setup required'}
        $ModelsNInferStatus.Foreground=if($installed){'#79E99A'}else{'#F1C66D'}
    }
    if($ModelsNInferAction){$ModelsNInferAction.Content=if($installed){'Repair NInfer'}else{'Set up NInfer'}}
}

function Update-BackendSelectionUi {
    $selected=Get-SelectedModel
    if(-not $selected){
        $PrimaryButton.IsEnabled=$false
        $PrimaryButton.Content=if($script:ModelScanOperation){'Discovering models...'}else{'Choose a model to start'}
        $StatusText.Text=if($script:ModelScanOperation){'AgentPort is checking known model locations in the background. You can keep using the window.'}else{'No model is selected. Open Manage models to choose what appears here.'}
        return
    }
    if(-not $script:StopOperation.Active -and $script:LaunchState -eq 'idle'){$PrimaryButton.IsEnabled=$true}
    $ninfer=($selected -and $selected.Source -eq 'NInfer')
    $team=($selected -and $selected.Source -eq 'Team')
    foreach($control in @($CacheCombo,$OffloadCombo,$SpecCombo)){if($control){$control.IsEnabled=-not ($ninfer -or $team)}}
    if($AdvancedSettings){$AdvancedSettings.IsEnabled=-not ($ninfer -or $team)}
    if($ContextCombo){$ContextCombo.IsEnabled=-not $team}
    if($team){
        $ContextCombo.SelectedItem='48k (49,152 tokens)'
        $PrimaryButton.Content=if($selected.Installed){'Start recommended local agent'}else{'Download and start recommended agent'}
        $StatusText.Text='Qwen3-Coder, 48k context and action-first filesystem, ComfyUI and Blender tools.'
        return
    }
    if($ninfer){
        $PrimaryButton.Content='Start NInfer and open Harness'
        $StatusText.Text='NInfer fast chat selected. Use the recommended 48k model instead for filesystem, ComfyUI or Blender tools.'
    } else {
        $PrimaryButton.Content='Start selected GGUF'
        $StatusText.Text='This existing model was discovered locally but has not passed AgentPort creative-tool verification.'
    }
}

function Select-AndStartNInfer {
    param([int]$Context=49152)
    if(-not (Test-AgentPortNInferInstalled)){
        $answer=[Windows.MessageBox]::Show("NInfer needs a one-time setup and its compatible model (about 15.8 GB).`n`nAgentPort will install it and open DeepSeek Harness with NInfer selected.`n`nContinue?",'Set up NInfer',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Information)
        if($answer -ne [Windows.MessageBoxResult]::Yes){return}
        Install-AgentPortNInfer $false
        if(-not (Test-AgentPortNInferInstalled)){return}
    }
    for($index=0;$index -lt $script:Models.Count;$index++){
        if($script:Models[$index].Source -eq 'NInfer'){$ModelCombo.SelectedIndex=$index;break}
    }
    $label=@($script:ContextPresets.Keys | Where-Object {$script:ContextPresets[$_] -eq $Context})[0]
    if($label){$ContextCombo.SelectedItem=$label}
    Start-UnifiedStack
}

function Get-AgentPortNInferSetupPath {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($script:AgentPortRoot){$candidates.Add((Join-Path $script:AgentPortRoot 'ninfer-4080\Bootstrap-NInfer4080.ps1'))}
    $candidates.Add((Join-Path $PSScriptRoot 'Bootstrap-NInfer4080.ps1'))
    $candidates.Add((Join-Path (Split-Path $PSScriptRoot -Parent) 'ninfer-4080\Bootstrap-NInfer4080.ps1'))
    foreach($candidate in @($candidates | Select-Object -Unique)){
        if(Test-Path -LiteralPath $candidate){return [IO.Path]::GetFullPath($candidate)}
    }
    throw "NInfer setup files are missing from this AgentPort installation. Re-download the complete AgentPort package."
}

function Install-AgentPortNInfer([bool]$ShowCompletion=$true) {
    $setup=Get-AgentPortNInferSetupPath
    $process=Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$setup+'"')) -Wait -PassThru
    if($process.ExitCode -eq 0){
        Refresh-Models
        Refresh-NInferControls
        Set-Log 'NInfer setup completed successfully.' 'ok'
        if($ShowCompletion){[Windows.MessageBox]::Show('NInfer is installed and ready. Choose Switch to NInfer to start it.','NInfer ready') | Out-Null}
    } else {[Windows.MessageBox]::Show('NInfer setup did not finish. The setup window contains the exact reason.','NInfer setup') | Out-Null}
}

function Update-NInferHarnessSettings {
    param([int]$Context,[int]$MaxTokens=4096)
    Ensure-ConfigDir
    $provider=@"
    ninfer-local:
      displayName: NInfer RTX 4080
      apiKeyEnv: NINFER_API_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:5100/v1
      defaultInput:
        - text
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      timeoutMs: 3600000
      streamIdleTimeoutMs: 3600000
      websocketConnectTimeoutMs: 3600000
      retryPolicy:
        mode: normal
        maxRetries: 0
      models:
        - id: 'qwen3.8-27b-minq4'
          name: 'Qwen3.8 27B min-Q4 (NInfer MTP3)'
          contextWindow: $Context
          maxTokens: $MaxTokens
"@
    if(Test-Path -LiteralPath $script:SettingsPath){$content=Get-Content -LiteralPath $script:SettingsPath -Raw}else{$content="llm-pi-ai:`n  providers:`n"}
    $legacyModel="(?m)^        - id:\s*['`"]?qwen3\.8-27b-minq4['`"]?\s*\r?\n(?:^          [^\r\n]*(?:\r?\n|$))*"
    $content=[regex]::Replace($content,$legacyModel,'')
    $legacyProviderPattern='(?ms)^    textgen-local:\s*\r?\n.*?(?=^    [A-Za-z0-9][A-Za-z0-9_-]*:\s*$|^[A-Za-z0-9][A-Za-z0-9_-]*:\s*$|\z)'
    $legacyProvider=[regex]::Match($content,$legacyProviderPattern)
    if($legacyProvider.Success -and $legacyProvider.Value -match '(?m)^      models:\s*$' -and $legacyProvider.Value -notmatch '(?m)^        - id:'){
        $content=$content.Remove($legacyProvider.Index,$legacyProvider.Length)
    }
    $providerPattern='(?ms)^    ninfer-local:\s*\r?\n.*?(?=^    [A-Za-z0-9][A-Za-z0-9_-]*:\s*$|^[A-Za-z0-9][A-Za-z0-9_-]*:\s*$|\z)'
    if($content -match $providerPattern){
        $content=[regex]::Replace($content,$providerPattern,$provider+"`n",1)
    } elseif($content -match '(?m)^\s{2}providers:\s*$'){
        $content=[regex]::Replace($content,'(?m)^(\s{2}providers:\s*\r?\n)',('${1}'+$provider+"`n"),1)
    } else {$content="llm-pi-ai:`n  providers:`n$provider`n"+$content}
    if($content -match '(?m)^agent-default-model:\s*$'){
        $content=[regex]::Replace($content,'(agent-default-model:\s*[\r\n]+\s*provider:\s*)[^\r\n]+([\r\n]+\s*model:\s*)[^\r\n]+',('${1}ninfer-local${2}'+"'qwen3.8-27b-minq4'"),1)
    } else {$content+="`nagent-default-model:`n  provider: ninfer-local`n  model: 'qwen3.8-27b-minq4'`n"}
    [IO.File]::WriteAllText($script:SettingsPath,$content,([Text.UTF8Encoding]::new($false)))
}

function New-NInferHarnessPatch {
    param([string]$Path,[string]$SettingsPath='')
    $lines=@("- id: session-title-llm`n  disabled: true")
    # The 16 GB NInfer artifact has a practical 24k window. Harness's built-in
    # tool schemas can exceed it, so this mode is reliable fast chat. The 48k
    # managed GGUF backend remains the agent/MCP path.
    foreach($id in @('tool-bash','tool-pwsh','tool-fs','tool-fs-search','tool-jobs','skill-filesystem','tool-skill','command-goal','tool-goal','planning','delegation','tool-ask-user','tool-todo','tool-web')){
        $lines+="- id: $id`n  disabled: true"
    }
    if($SettingsPath){$lines+= "- id: settings`n  config:`n    path: '"+$SettingsPath.Replace('\','/').Replace("'","''")+"'"}
    $globalPatch=Join-Path $env:USERPROFILE '.dsh\cordis.patch.yml'
    if(Test-Path $globalPatch){
        $text=Get-Content $globalPatch -Raw
        foreach($match in [regex]::Matches($text,'(?m)^[ \t]*- id: ([A-Za-z0-9_-]+)\r?\n\s+name: [''"]?@deepseek-ai/dsh-mcp-client')){
            $lines+="- id: $($match.Groups[1].Value)`n  disabled: true"
        }
    }
    if(-not $lines.Count){$lines=@('[]')}
    [IO.File]::WriteAllText($Path,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    return $Path
}

function Start-AgentPortNInfer {
    try {
        $PrimaryButton.IsEnabled=$false
        Kill-Stack
        Start-Sleep -Milliseconds 700
        if((Test-Port 3080) -or (Test-Port 5100)){throw 'A backend started outside AgentPort is still running. Close it, then retry.'}
        $selectedLabel=[string]$ContextCombo.SelectedItem
        $selectedContext=[int]$script:ContextPresets[$selectedLabel]
                $context=if($selectedContext -ge 49152){49152}elseif($selectedContext -ge 32768){32768}else{24576}
        $profile=if($context -eq 49152){'maximum 49k context'}elseif($context -eq 32768){'balanced 32k tools context'}else{'fast/reliable 24k context'}
        Set-LaunchPhase 1 'Starting NInfer' ("Loading Qwen3.8 27B min-Q4, $profile, MTP3.") 20
        if($script:NInferState){Stop-NInferService $script:NInferState; $script:NInferState=$null}
        $attempts=@($context,32768,24576,16384)|Where-Object {$_ -le $context}|Select-Object -Unique
        $lastCapacityError=''
        foreach($candidate in $attempts){
            try{
                $context=[int]$candidate
                $script:NInferState=Start-NInferService -Distro (Get-AgentPortNInferDistro) -Context $context -Draft 3
                break
            }catch{
                $lastCapacityError=$_.Exception.Message
                if($lastCapacityError -notmatch 'runtime reservation|capacity|out of memory|CUDA.*memory'){throw}
                Set-Log ("NInfer context $context did not fit. Retrying the next stable fast-chat size.") 'warn'
                Set-LaunchPhase 1 'Adjusting for available VRAM' 'Reducing NInfer chat context to fit the current free VRAM.' 24
                Start-Sleep -Milliseconds 500
            }
        }
        if(-not $script:NInferState){throw $lastCapacityError}
        $script:PendingModel=$script:NInferState.Model
        $script:PendingContext=$script:NInferState.Context
        $body=@{model=$script:PendingModel;messages=@(@{role='user';content='Reply READY.'});max_tokens=16;temperature=0;stream=$false}
        $null=Invoke-TextGenApi '/v1/chat/completions' 'POST' $body 60
        $harnessMaxTokens=if($script:PendingContext -ge 49152){8192}else{4096}
        Update-NInferHarnessSettings $script:PendingContext $harnessMaxTokens
        $script:Config.last_model=$script:PendingModel
        $script:Config.active_model=$script:PendingModel
        $script:Config.active_context_tokens=$script:PendingContext
        $script:Config.active_offload_mode='NInfer MTP3 (full GPU)'
        Save-Config
        Set-Log ("NInfer verified | stock Qwen3.8 27B min-Q4 | $context context | INT4 KV | MTP3") 'ok'
        Set-LaunchPhase 6 'Starting fast chat' 'NInfer completion verified. Harness tools are disabled in this memory-limited mode.' 92
        $script:NInferHarnessPatch=New-NInferHarnessPatch (Join-Path $script:NInferState.LogDirectory 'coding.patch.yml')
        Start-Harness
        $script:LaunchState='wait_harness'
        $script:LaunchDeadline=(Get-Date).AddSeconds(120)
    } catch {
        $rawError=$_.Exception.Message
        if($script:NInferState){Stop-NInferService $script:NInferState; $script:NInferState=$null}
        $script:LaunchState='idle'
        $PrimaryButton.IsEnabled=$true
            $friendlyError=if($rawError -match 'runtime reservation|capacity|out of memory|CUDA.*memory'){
                $freeMatch=[regex]::Match($rawError,'(?<free>\d+)\s*MiB is free')
                if($freeMatch.Success){
                    $freeMiB=[int]$freeMatch.Groups['free'].Value
                    "NInfer needs about 14.6 GiB of free GPU memory, but only $([math]::Round($freeMiB/1024,1)) GiB is free. Stop the current backend, ComfyUI, Blender, or another GPU app, then retry."
                } else {
                    'NInfer could not reserve enough GPU memory for this profile. Stop the current backend, ComfyUI, Blender, or another GPU app, then retry.'
                }
        } elseif($rawError -match 'test -x|test -s|engine or artifact|control command failed'){
            'NInfer setup is incomplete. Open Models and choose Repair NInfer, then try again.'
        } elseif($rawError -match 'Port 5100|already occupied|still running'){
            'Another local AI backend is still using port 5100. Open Runtimes, stop everything, then try again.'
        } else {
            'NInfer could not start. Open Models and choose Repair NInfer, then try again.'
        }
        Set-LaunchPhase 1 'NInfer could not start' $friendlyError 0 'error'
        Set-Log $rawError 'error'
        [System.Windows.MessageBox]::Show($friendlyError,'NInfer could not start') | Out-Null
    }
}
