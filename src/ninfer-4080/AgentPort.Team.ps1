function Get-AgentPortTeamRuntime {
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'AgentPort\llama-b10809') -Filter llama-server.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

function Get-AgentPortTeamModel {
    $name='Qwen3-Coder-30B-A3B-Instruct-UD-IQ3_XXS.gguf'
    $managed=Join-Path $env:LOCALAPPDATA ('AgentPort\models\'+$name)
    if(Test-Path $managed){return $managed}
    # Reuse an exact existing download instead of consuming another 12.8 GB.
    foreach($root in @([string]$script:Config.models_root,[string]$script:Config.textgen_root)){
        if($root -and (Test-Path $root)){
            $found=Get-ChildItem -LiteralPath $root -Filter $name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            if($found){return $found}
        }
    }
    return $managed
}

function Save-AgentPortPreview($Visual,[string]$Name){
    $path=Join-Path $env:LOCALAPPDATA ('AgentPort\preview-'+$Name+'.png')
    $Visual.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$Visual.ActualWidth,[int]$Visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Visual)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $file=[IO.File]::Create($path);try{$encoder.Save($file)}finally{$file.Dispose()}
}

function Update-AgentPortTeamMetrics {
    if(-not $TokenStats){return}
    if($script:PendingModel -ne 'agentport-fast-qwen3-coder'){$TokenStats.Text='Token speed appears after the recommended agent starts.';return}
    try{
        $body=(Invoke-WebRequest http://127.0.0.1:5100/metrics -Headers @{Authorization='Bearer local-textgen'} -UseBasicParsing -TimeoutSec 1).Content
        $values=@{}
        foreach($match in [regex]::Matches($body,'(?m)^llamacpp:([a-z_]+)\s+([0-9.eE+-]+)\s*$')){$values[$match.Groups[1].Value]=[double]::Parse($match.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)}
        $rate=if($values.tokens_predicted_seconds_total -gt 0){$values.tokens_predicted_total/$values.tokens_predicted_seconds_total}else{0}
        $TokenStats.Text=('Decoder average: {0:N1} tok/s' -f $rate)+"`n"+('Input processed: {0:N0} | Cached: {1:N0}' -f $values.prompt_tokens_total,$values.prompt_tokens_cached_total)+"`n"+('Generated: {0:N0} tokens | Active requests: {1:N0}' -f $values.tokens_predicted_total,$values.requests_processing)
    }catch{$TokenStats.Text='Waiting for token statistics...'}
}

function Install-AgentPortTeamPreset {
    $text=[IO.File]::ReadAllText((Find-AgentPortStandardPreset))
    # Keep the everyday catalog small. Deliberate planning, jobs, delegation and
    # confirmation tools are unnecessary for this single local creative agent.
    foreach($id in @('agent-instructions','tool-jobs','planning','tool-ask-user','delegation','command-goal','tool-goal','tool-todo','tool-web')){
        $text=[regex]::Replace($text,'(?ms)^- id: '+$id+'\r?\n.*?(?=^- id: |\z)','')
    }
    $persona=@'
    prefix: |-
      You are a practical local assistant. Complete the user's task using the available tools. Inspect briefly, act, and verify. Continue through ordinary tool results until the task is complete; do not require the user to say continue. Ask only for a material missing choice or required permission. Keep replies short and stop when done.
      Use ComfyUI and Blender MCP tools directly. They do not require a corresponding skill. Inspect installed models/nodes or the scene before editing. Never claim success without a tool result. For filesystem tasks use the filesystem tools. Never delete or overwrite unrelated work. If a tool fails, try one focused correction, then report the actual blocker. Do not install extra skills or delegate routine tasks.
'@
    $text=[regex]::Replace($text,'(?ms)(^- id: persona\r?\n.*?  config:\r?\n).*?(?=^- id: )',{param($m)$m.Groups[1].Value+$persona+"`n`n"},1)
    $skills=([string]$script:Config.harness_skills_root).Replace('\','/').Replace("'","''")
    $text=[regex]::Replace($text,'(?m)^(  name: [''"]?@deepseek-ai/dsh-skill-filesystem[''"]?)\s*$',('$1'+"`n  config:`n    includeDefaultRoots: false`n    customSkillDirs:`n      - '$skills'"))
    $root=Join-Path $env:USERPROFILE '.dsh\.agent-presets\agentport-fast'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $file=Join-Path $root 'agent.cordis.yml'
    if(Test-Path $file){Copy-Item -LiteralPath $file -Destination ($file+'.backup') -Force}
    [IO.File]::WriteAllText($file,$text,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'preset.yml'),"name: AgentPort Fast`ndescription: Action-first local agent with filesystem, ComfyUI and Blender tools.`norder: 0`n",[Text.UTF8Encoding]::new($false))
    [void](Set-AgentPortPresetDefault -Path $script:SettingsPath -Preset 'agentport-fast' -BackupSuffix '.before-team')
}

function Start-AgentPortTeam {
    if($script:TeamStarting){return};$script:TeamStarting=$true
    try{
        $PrimaryButton.IsEnabled=$false
        # Some Windows NVIDIA driver builds leave LASTEXITCODE as -1 when the
        # query is piped through Select-Object, despite returning a valid name.
        # The returned adapter name is the reliable capability check here.
        $gpu=(& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1)
        if(-not $gpu -or $gpu -notmatch 'RTX\s+(30|40)\d\d'){throw 'The recommended setup currently targets NVIDIA RTX 30 and 40 series GPUs. Install the NVIDIA driver, or choose an existing model.'}
        $gpuMemoryLine=(& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
        if($gpuMemoryLine -and [double]$gpuMemoryLine -lt 7000){throw 'This recommended 30B setup needs at least 8 GB of NVIDIA VRAM. Choose a smaller existing GGUF on this GPU.'}
        if([double]$script:RamGB -lt 24){throw 'This recommended setup needs at least 24 GB of system RAM so it can safely spill model layers when VRAM is busy.'}
        Ensure-AgentPortRuntimeDirs
        $model=Get-AgentPortTeamModel
        if(-not(Get-AgentPortTeamRuntime) -or -not(Test-Path $model)){
            $drive=Get-PSDrive -Name ([IO.Path]::GetPathRoot($env:LOCALAPPDATA).TrimEnd(':\')) -ErrorAction SilentlyContinue
            if($drive -and $drive.Free -lt 16GB){throw ('AgentPort needs about 16 GB free for the model and runtime. Free space on '+$drive.Name+':, then retry.')}
            Set-LaunchPhase 1 'Installing your local agent' 'Downloading Qwen3-Coder and the Windows CUDA runtime (about 13.6 GB). Downloads resume if interrupted.' 12
            $log=Join-Path $script:AppDataDir 'team-install'
            $p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Install-Team.ps1')+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput ($log+'.out.log') -RedirectStandardError ($log+'.err.log')
            $clock=[Diagnostics.Stopwatch]::StartNew()
            while(-not $p.HasExited){
                if($clock.Elapsed.TotalMinutes -gt 60){& taskkill.exe /PID $p.Id /T /F | Out-Null;throw 'Download timed out. Click Download and start again to resume.'}
                if(Test-Path ($model+'.part')){
                    $downloaded=(Get-Item ($model+'.part')).Length
                    Set-LaunchPhase 1 'Downloading Qwen3-Coder' ('{0:N1} / 12.8 GB downloaded.' -f ($downloaded/1e9)) ([int](12+30*[math]::Min(1,$downloaded/12848766112)))
                }
                [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 150;$p.Refresh()
            }
            if($p.ExitCode -ne 0){throw "Setup failed. See $log.err.log, then retry."}
            $model=Get-AgentPortTeamModel
        }
        Set-LaunchPhase 2 'Preparing tools and Harness' 'Preparing the local agent and compact MCP tool catalogue.' 45
        $checker=Join-Path $script:AppDataDir 'mcp\checker\Scripts\python.exe'
        if(-not(Test-Path $checker)){Invoke-AgentPortMcpInstall 'checker'}
        try{$null=Find-AgentPortStandardPreset}catch{Install-DeepSeekHarness}
        Prepare-IsolatedHarnessSkills
        Update-HarnessSettings 'agentport-fast-qwen3-coder' 'Qwen3-Coder 30B A3B - AgentPort Fast' 49152 4096
        Install-AgentPortTeamPreset
        Kill-Stack
        if(Test-Port 5100){throw 'Another app is using port 5100. Close that backend and retry.'}
        $logs=Join-Path $script:AppDataDir 'team-logs';New-Item -ItemType Directory -Force -Path $logs | Out-Null
        Set-LaunchPhase 3 'Loading Qwen3-Coder' '48k context, action-first preset and protected GPU headroom. ComfyUI and Blender remain open.' 65
        $script:TextGenProcess=Start-Process (Get-AgentPortTeamRuntime) -ArgumentList @('-m',('"'+$model+'"'),'--host','127.0.0.1','--port','5100','--api-key','local-textgen','--alias','agentport-fast-qwen3-coder','-c','49152','-ngl','99','--fit-target','768','-ctk','q4_0','-ctv','q4_0','--parallel','1','--reasoning','off','--no-reasoning-preserve','--metrics') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'llama.out.log') -RedirectStandardError (Join-Path $logs 'llama.err.log')
        $script:TextGenOwnership=Get-AgentPortProcessRecord ([int]$script:TextGenProcess.Id) $script:TextGenProcess
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while($true){
            $script:TextGenProcess.Refresh()
            if($script:TextGenProcess.HasExited){throw "The model could not load. See $logs\llama.err.log. Close other loaded GPU models and retry."}
            try{$ready=Invoke-RestMethod http://127.0.0.1:5100/health -TimeoutSec 1;if($ready.status -eq 'ok'){break}}catch{}
            if($clock.Elapsed.TotalMinutes -gt 5){throw 'Model loading timed out. Check Home logs.'}
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 200
        }
        $script:PendingModel='agentport-fast-qwen3-coder';$script:PendingContext=49152
        $script:Config.last_model=$script:PendingModel;$script:Config.active_model=$script:PendingModel
        $script:Config.active_context_tokens=49152;$script:Config.active_offload_mode='AgentPort Fast';Save-Config
        $script:TeamHarnessPatch=New-NInferHarnessPatch (Join-Path $logs 'harness.patch.yml')
        Start-Harness
        $script:LaunchState='wait_harness';$script:LaunchDeadline=(Get-Date).AddMinutes(3)
        Set-LaunchPhase 6 'Opening your local agent' 'Starting Harness with Qwen3-Coder, filesystem tools and enabled MCPs.' 92
    }catch{
        Write-Host ('Recommended agent startup failed: '+$_.Exception.Message)
        Stop-AgentPortProcess $script:TextGenProcess;$script:TextGenProcess=$null
        Set-LaunchPhase 1 'Setup needs attention' $_.Exception.Message 100 'error'
        Set-Log $_.Exception.Message 'error';$script:LaunchState='idle'
    }finally{$script:TeamStarting=$false;$PrimaryButton.IsEnabled=$true}
}
