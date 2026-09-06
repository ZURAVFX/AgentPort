# NInfer is selected as its own model in AgentPort's existing model selector.
function Stop-AgentPortProcess {
    param($Process)
    if(-not $Process){return}
    $Process.Refresh()
    if($Process.HasExited){return}
    $current=Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if($current -and $current.StartTime -eq $Process.StartTime){
        & taskkill.exe /PID $Process.Id /T /F | Out-Null
    }
}

function Stop-VerifiedAgentPortProcess {
    param([int]$Port,[ValidateSet('backend','harness')][string]$Kind)
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    foreach($listener in $listeners){
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if(-not $process){continue}
        $command=[string]$process.CommandLine
        $executable=[string]$process.ExecutablePath
        $allowed=if($Kind -eq 'harness'){
            $command -like '*dsh web*' -or $command -like '*apps/cli/src/bin.ts*"web"*' -or
            ($script:Config.harness_root -and $command -like ('*'+[string]$script:Config.harness_root+'*'))
        } else {
            $command -like '*llama-server*' -or
            ($command -like '*server.py*' -and $script:Config.textgen_root -and $executable -like ([string]$script:Config.textgen_root+'*'))
        }
        if($allowed){& taskkill.exe /PID $process.ProcessId /T /F | Out-Null}
    }
}

function Stop-StaleNInferInstances {
    $temp=Join-Path $env:LOCALAPPDATA 'AgentPort/ninfer-stop'
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $distro=Get-AgentPortNInferDistro
    $linuxHome=((& wsl.exe -d $distro --exec printenv HOME) -join '').Trim()
    if($linuxHome -notmatch '^/[A-Za-z0-9._/-]+$'){return}
    $exe="$linuxHome/.agentport/ninfer-src/build-sm89/apps/ninfer-serve"
    $command=@'
set -eu
for file in '__ROOT__'/logs/agentport-*.pid '__ROOT__'/logs/agentport.pid; do
  test -f "$file" || continue
  read -r target < "$file"
  case "$target" in ''|*[!0-9]*) continue;; esac
  if test "$(readlink /proc/$target/exe 2>/dev/null || true)" = '__EXE__'; then kill -TERM "$target"; fi
  rm -f "$file"
done
'@
    try {Invoke-NInferShell $distro ($command.Replace('__ROOT__',"$linuxHome/.agentport").Replace('__EXE__',$exe)) $temp | Out-Null}catch{}
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
    $ninfer=($selected -and $selected.Source -eq 'NInfer')
    foreach($control in @($CacheCombo,$OffloadCombo,$SpecCombo)){if($control){$control.IsEnabled=-not $ninfer}}
    if($AdvancedSettings){$AdvancedSettings.IsEnabled=-not $ninfer}
    if($ninfer){
        $PrimaryButton.Content='Start NInfer and open Harness'
        $StatusText.Text='NInfer selected. Start will stop AgentPort-owned TextGen, Harness and older NInfer instances before loading the fast profile.'
    } else {
        $PrimaryButton.Content='Start TextGen and open Harness'
        $StatusText.Text='The selected GGUF will use TextGen with DeepSeek Harness.'
    }
}

function Select-AndStartNInfer {
    param([int]$Context=24576)
    if(-not (Test-AgentPortNInferInstalled)){
        $answer=[Windows.MessageBox]::Show("NInfer needs a one-time setup and its compatible model (about 15.8 GB).`n`nAgentPort will install it, switch away from TextGen and open DeepSeek Harness with NInfer selected.`n`nContinue?",'Set up NInfer',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Information)
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
        $context=if($selectedContext -ge 49152){49152}else{24576}
        $profile=if($context -eq 49152){'maximum 49k context'}else{'fast/reliable 24k context'}
        Set-LaunchPhase 1 'Starting NInfer' ("Loading Qwen3.8 27B min-Q4, $profile, MTP3.") 20
        if($script:NInferState){Stop-NInferService $script:NInferState; $script:NInferState=$null}
        try {
            $script:NInferState=Start-NInferService -Distro (Get-AgentPortNInferDistro) -Context $context -Draft 3
        } catch {
            $startupError=$_.Exception.Message
            $capacityFailure=$startupError -match 'runtime reservation|capacity|out of memory|CUDA.*memory'
            if($context -eq 49152 -and $capacityFailure){
                Set-Log '49k context did not fit in the currently available VRAM. Retrying automatically at 24k.' 'warn'
                Set-LaunchPhase 1 'Adjusting for available VRAM' '49k did not fit, so AgentPort is retrying with the fast and reliable 24k context.' 24
                $context=24576
                $profile='fast/reliable 24k context'
                $label=@($script:ContextPresets.Keys | Where-Object {$script:ContextPresets[$_] -eq 24576})[0]
                if($label){$ContextCombo.SelectedItem=$label}
                Start-Sleep -Milliseconds 500
                $script:NInferState=Start-NInferService -Distro (Get-AgentPortNInferDistro) -Context $context -Draft 3
            } else {throw}
        }
        $script:PendingModel=$script:NInferState.Model
        $script:PendingContext=$script:NInferState.Context
        $body=@{model=$script:PendingModel;messages=@(@{role='user';content='Reply READY.'});max_tokens=16;temperature=0;stream=$false}
        $null=Invoke-TextGenApi '/v1/chat/completions' 'POST' $body 60
        Update-NInferHarnessSettings $script:PendingContext 4096
        $script:Config.last_model=$script:PendingModel
        $script:Config.active_model=$script:PendingModel
        $script:Config.active_context_tokens=$script:PendingContext
        $script:Config.active_offload_mode='NInfer MTP3 (full GPU)'
        Save-Config
        Set-Log ("NInfer verified | stock Qwen3.8 27B min-Q4 | $context context | INT4 KV | MTP3") 'ok'
        Set-LaunchPhase 6 'Starting Harness' 'NInfer completion verified. Connecting Harness.' 92
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
                "NInfer needs about 14.6 GiB of free GPU memory, but only $([math]::Round($freeMiB/1024,1)) GiB is free. Stop TextGen, Harness, ComfyUI, Blender, or another GPU app, then retry the 24k profile."
            } else {
                'NInfer could not reserve enough GPU memory for this profile. Stop TextGen, Harness, ComfyUI, Blender, or another GPU app, then retry the 24k profile.'
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
