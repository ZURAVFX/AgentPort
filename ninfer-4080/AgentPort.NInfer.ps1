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
        if(Test-Port 3080){throw 'Close the existing Harness before switching to the NInfer coding profile.'}
        Set-LaunchPhase 1 'Starting NInfer' 'Loading Qwen3.8 27B min-Q4, 24k context, MTP3.' 20
        if($script:NInferState){Stop-NInferService $script:NInferState; $script:NInferState=$null}
        $script:NInferState=Start-NInferService -Distro (Get-AgentPortNInferDistro) -Context 24576 -Draft 3
        $script:PendingModel=$script:NInferState.Model
        $script:PendingContext=$script:NInferState.Context
        $body=@{model=$script:PendingModel;messages=@(@{role='user';content='Reply READY.'});max_tokens=16;temperature=0;stream=$false}
        $null=Invoke-TextGenApi '/v1/chat/completions' 'POST' $body 60
        Update-HarnessSettings $script:PendingModel 'Qwen3.8 27B min-Q4 (NInfer)' $script:PendingContext 4096
        $script:Config.last_model=$script:PendingModel
        $script:Config.active_model=$script:PendingModel
        $script:Config.active_context_tokens=$script:PendingContext
        Save-Config
        Set-Log 'NInfer verified | stock Qwen3.8 27B min-Q4 | 24,576 context | INT4 KV | MTP3' 'ok'
        Set-LaunchPhase 6 'Starting Harness' 'NInfer completion verified. Connecting Harness.' 92
        $script:NInferHarnessPatch=New-NInferHarnessPatch (Join-Path $script:NInferState.LogDirectory 'coding.patch.yml')
        Start-Harness
        $script:LaunchState='wait_harness'
        $script:LaunchDeadline=(Get-Date).AddSeconds(120)
    } catch {
        if($script:NInferState){Stop-NInferService $script:NInferState; $script:NInferState=$null}
        $script:LaunchState='idle'
        $PrimaryButton.IsEnabled=$true
        Set-LaunchPhase 1 'NInfer could not start' $_.Exception.Message 0 'error'
        Set-Log $_.Exception.Message 'error'
        [System.Windows.MessageBox]::Show($_.Exception.Message+"`n`nRun Install-NInfer4080.cmd if the engine or artifact is missing. Close any existing local model before switching backends.",'NInfer startup') | Out-Null
    }
}
