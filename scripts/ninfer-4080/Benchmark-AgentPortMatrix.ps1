[CmdletBinding()]
param(
    [int]$Runs = 3,
    [int]$MaxTokens = 512,
    [int]$Context = 49152,
    [string]$Prompt = 'Write a compact but complete Python implementation of an LRU cache with type hints, then explain its time complexity.',
    [string]$Distro = 'Ubuntu-24.04',
    [switch]$SkipNInfer
)

$ErrorActionPreference = 'Stop'
$ConfigFile = Join-Path $env:USERPROFILE '.dsh\launcher_config.json'
if(-not (Test-Path -LiteralPath $ConfigFile)){ throw "AgentPort config not found: $ConfigFile" }
$config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
$textgenRoot = [string]$config.textgen_root
if(-not $textgenRoot){ $textgenRoot = Join-Path $env:PUBLIC 'AgentPort\textgen' }
$flagsFile = Join-Path $textgenRoot 'user_data\CMD_FLAGS.txt'
$python = Join-Path $textgenRoot 'installer_files\env\python.exe'
$conda = Join-Path $textgenRoot 'installer_files\conda\condabin\conda.bat'
$server = Join-Path $textgenRoot 'server.py'
$baseUrl = 'http://127.0.0.1:5100/v1'
$apiKey = 'local-textgen'
$headers = @{ Authorization = "Bearer $apiKey"; 'Content-Type'='application/json' }

foreach($p in @($flagsFile,$python,$conda,$server)){
    if(-not (Test-Path -LiteralPath $p)){ throw "Required AgentPort/TextGen file missing: $p" }
}

$originalFlags = Get-Content -LiteralPath $flagsFile -Raw
if(-not $originalFlags.Trim()){ throw "TextGen CMD_FLAGS.txt is empty: $flagsFile" }

function Get-SelectedModel([string]$Flags){
    $m = [regex]::Match($Flags,'(?m)^--model\s+"?([^"\r\n]+)"?\s*$')
    if($m.Success){ return $m.Groups[1].Value.Trim() }
    if($config.active_model){ return [string]$config.active_model }
    if($config.last_model){ return [string]$config.last_model }
    throw 'Could not determine the selected model from AgentPort/TextGen.'
}

$model = Get-SelectedModel $originalFlags
Write-Host ''
Write-Host 'AgentPort RTX 4080 benchmark matrix' -ForegroundColor Cyan
Write-Host ('Model:   {0}' -f $model)
Write-Host ('Context: {0:N0}' -f $Context)
Write-Host ('Runs:    {0} measured + 1 warmup per mode' -f $Runs)
Write-Host ('Output:  up to {0:N0} tokens per request' -f $MaxTokens)
Write-Host ''

function Stop-LocalBackend {
    Get-NetTCPConnection -State Listen -LocalPort 5100 -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like '*llama-server.exe*' -or
        ($_.CommandLine -like '*installer_files\env\python.exe*server.py*' -and $_.CommandLine -like ('*'+$textgenRoot+'*'))
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    try { & wsl.exe -d $Distro -- bash -lc "pkill -f 'ninfer-serve.*--port 5100' >/dev/null 2>&1 || true" 2>$null | Out-Null } catch {}
    Start-Sleep -Milliseconds 700
}

function Wait-Api([int]$TimeoutSec=180){
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while((Get-Date) -lt $deadline){
        try{
            $r = Invoke-RestMethod -Uri ($baseUrl+'/models') -Headers $headers -TimeoutSec 2
            if($r){ return $r }
        }catch{}
        Start-Sleep -Milliseconds 750
    }
    throw "API did not become ready at $baseUrl within $TimeoutSec seconds."
}

function Start-TextGenBackend {
    $logDir = Join-Path $textgenRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $out = Join-Path $logDir 'benchmark-textgen.out.log'
    $err = Join-Path $logDir 'benchmark-textgen.err.log'
    Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
    $envDir = Join-Path $textgenRoot 'installer_files\env'
    $cmd = 'set "PYTHONNOUSERSITE=1"&& set "PYTHONPATH="&& set "PYTHONHOME="&& set "PYTHONUTF8=1"&& set "CUDA_PATH={0}"&& set "CUDA_HOME={0}"&& call "{1}" activate "{0}" && "{2}" server.py > "{3}" 2> "{4}"' -f $envDir,$conda,$python,$out,$err
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/s','/c',$cmd -WorkingDirectory $textgenRoot -WindowStyle Hidden | Out-Null
    try { Wait-Api 180 | Out-Null }
    catch {
        $tail = if(Test-Path $err){ (Get-Content $err -Tail 80) -join "`n" }else{ 'No TextGen error log found.' }
        throw "TextGen failed to start.`n$tail"
    }
}

function Set-TextGenMode([string]$Name){
    $lines = @($originalFlags -split "`r?`n" | Where-Object { $_.Trim() })
    $lines = @($lines | Where-Object {
        $_ -notmatch '^--spec-type\b' -and
        $_ -notmatch '^--spec-ngram-size-n\b' -and
        $_ -notmatch '^--spec-ngram-size-m\b' -and
        $_ -notmatch '^--draft-max\b' -and
        $_ -notmatch '^--spec-draft-n-max\b'
    })

    $ctxChanged = $false
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i] -match '^--ctx-size\b'){
            $lines[$i] = '--ctx-size '+$Context
            $ctxChanged = $true
        }
    }
    if(-not $ctxChanged){ $lines += '--ctx-size '+$Context }

    switch($Name){
        'TextGen Off' {}
        'NGram Conservative' { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 16'; $lines += '--spec-ngram-size-m 32' }
        'NGram Medium'       { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 24'; $lines += '--spec-ngram-size-m 48' }
        'NGram Aggressive'   { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 32'; $lines += '--spec-ngram-size-m 64' }
        'MTP2'               { $lines += '--spec-type draft-mtp'; $lines += '--draft-max 2' }
        'MTP4'               { $lines += '--spec-type draft-mtp'; $lines += '--draft-max 4' }
        'MTP6'               { $lines += '--spec-type draft-mtp'; $lines += '--draft-max 6' }
        default              { throw "Unknown TextGen benchmark mode: $Name" }
    }
    [IO.File]::WriteAllLines($flagsFile,$lines,([Text.UTF8Encoding]::new($false)))
}

function Test-NInferReady {
    if($SkipNInfer){ return $false }
    try{
        & wsl.exe -d $Distro -- bash -lc "test -x ~/.agentport/ninfer-src/build-sm89/apps/ninfer-serve -a -s ~/.agentport/models/qwen3_8_27b_minq4.ninfer" 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    }catch{ return $false }
}

function Start-NInferBackend {
    $safeModel = $model.Replace("'",'')
    $cmd = "mkdir -p ~/.agentport/logs; nohup ~/.agentport/ninfer-src/build-sm89/apps/ninfer-serve ~/.agentport/models/qwen3_8_27b_minq4.ninfer --host 0.0.0.0 --port 5100 --api-key local-textgen --model-id '$safeModel' --max-context $Context --kv-capacity $Context --max-concurrency 1 --prefill-chunk 64 --kv-dtype i4 --spec mtp --draft-tokens 3 --lm-head-draft --preserve-thinking > ~/.agentport/logs/ninfer-benchmark.log 2>&1 < /dev/null &"
    & wsl.exe -d $Distro -- bash -lc $cmd | Out-Null
    if($LASTEXITCODE -ne 0){ throw "WSL NInfer launch exited $LASTEXITCODE" }
    try { Wait-Api 180 | Out-Null }
    catch {
        $tail = & wsl.exe -d $Distro -- bash -lc "tail -n 80 ~/.agentport/logs/ninfer-benchmark.log 2>/dev/null || true"
        throw "NInfer failed to start.`n$($tail -join "`n")"
    }
}

function Get-ApiModelId {
    try{
        $m = Invoke-RestMethod -Uri ($baseUrl+'/models') -Headers $headers -TimeoutSec 5
        if($m.data -and $m.data.Count -gt 0 -and $m.data[0].id){ return [string]$m.data[0].id }
    }catch{}
    return $model
}

function Invoke-OneRequest([string]$ApiModel,[int]$TokenLimit){
    $body = @{
        model = $ApiModel
        messages = @(@{ role='user'; content=$Prompt })
        max_tokens = $TokenLimit
        temperature = 0
        stream = $false
    } | ConvertTo-Json -Depth 8
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri ($baseUrl+'/chat/completions') -Headers $headers -Body $body -TimeoutSec 900
    $sw.Stop()
    $completion = if($response.usage -and $response.usage.completion_tokens){ [int]$response.usage.completion_tokens }else{ 0 }
    $promptTokens = if($response.usage -and $response.usage.prompt_tokens){ [int]$response.usage.prompt_tokens }else{ 0 }
    $tps = if($completion -gt 0 -and $sw.Elapsed.TotalSeconds -gt 0){ $completion / $sw.Elapsed.TotalSeconds }else{ 0 }
    [pscustomobject]@{
        PromptTokens = $promptTokens
        CompletionTokens = $completion
        Seconds = $sw.Elapsed.TotalSeconds
        TokPerSec = $tps
    }
}

function Get-VramUsedMiB {
    try{
        $v = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1).Trim()
        if($v -match '^\d+$'){ return [int]$v }
    }catch{}
    return 0
}

$results = @()
$textGenModes = @('TextGen Off','NGram Conservative','NGram Medium','NGram Aggressive','MTP2','MTP4','MTP6')

try{
    foreach($mode in $textGenModes){
        Write-Host ('[{0}/{1}] {2}' -f ($results.Count+1),($textGenModes.Count + ($(if(Test-NInferReady){1}else{0}))),$mode) -ForegroundColor Yellow
        try{
            Stop-LocalBackend
            Set-TextGenMode $mode
            Start-TextGenBackend
            $apiModel = Get-ApiModelId

            Write-Host '  warmup...' -NoNewline
            $warm = Invoke-OneRequest $apiModel ([Math]::Min(128,$MaxTokens))
            Write-Host (' {0:N1}s' -f $warm.Seconds)

            $samples = @()
            for($r=1;$r -le $Runs;$r++){
                $x = Invoke-OneRequest $apiModel $MaxTokens
                $samples += $x
                Write-Host ('  run {0}: {1:N2} tok/s  ({2} tokens, {3:N2}s)' -f $r,$x.TokPerSec,$x.CompletionTokens,$x.Seconds)
            }
            $valid = @($samples | Where-Object CompletionTokens -gt 0)
            if(-not $valid.Count){ throw 'API returned no completion token counts.' }
            $avg = ($valid | Measure-Object TokPerSec -Average).Average
            $min = ($valid | Measure-Object TokPerSec -Minimum).Minimum
            $max = ($valid | Measure-Object TokPerSec -Maximum).Maximum
            $results += [pscustomobject]@{
                Backend='TextGen'
                Mode=$mode
                AverageTokPerSec=[math]::Round($avg,2)
                MinTokPerSec=[math]::Round($min,2)
                MaxTokPerSec=[math]::Round($max,2)
                VramMiB=Get-VramUsedMiB
                Status='OK'
            }
        }catch{
            Write-Warning ("$mode failed: "+$_.Exception.Message)
            $results += [pscustomobject]@{Backend='TextGen';Mode=$mode;AverageTokPerSec=0;MinTokPerSec=0;MaxTokPerSec=0;VramMiB=Get-VramUsedMiB;Status='FAILED'}
        }
        Write-Host ''
    }

    if(Test-NInferReady){
        $mode='NInfer MTP3'
        Write-Host ('Testing {0}' -f $mode) -ForegroundColor Magenta
        try{
            Stop-LocalBackend
            Start-NInferBackend
            $apiModel = Get-ApiModelId
            Write-Host '  warmup...' -NoNewline
            $warm = Invoke-OneRequest $apiModel ([Math]::Min(128,$MaxTokens))
            Write-Host (' {0:N1}s' -f $warm.Seconds)
            $samples=@()
            for($r=1;$r -le $Runs;$r++){
                $x=Invoke-OneRequest $apiModel $MaxTokens
                $samples += $x
                Write-Host ('  run {0}: {1:N2} tok/s  ({2} tokens, {3:N2}s)' -f $r,$x.TokPerSec,$x.CompletionTokens,$x.Seconds)
            }
            $valid=@($samples | Where-Object CompletionTokens -gt 0)
            if(-not $valid.Count){ throw 'API returned no completion token counts.' }
            $avg=($valid|Measure-Object TokPerSec -Average).Average
            $min=($valid|Measure-Object TokPerSec -Minimum).Minimum
            $max=($valid|Measure-Object TokPerSec -Maximum).Maximum
            $results += [pscustomobject]@{Backend='NInfer';Mode=$mode;AverageTokPerSec=[math]::Round($avg,2);MinTokPerSec=[math]::Round($min,2);MaxTokPerSec=[math]::Round($max,2);VramMiB=Get-VramUsedMiB;Status='OK'}
        }catch{
            Write-Warning ("NInfer failed: "+$_.Exception.Message)
            $results += [pscustomobject]@{Backend='NInfer';Mode=$mode;AverageTokPerSec=0;MinTokPerSec=0;MaxTokPerSec=0;VramMiB=Get-VramUsedMiB;Status='FAILED'}
        }
    }else{
        Write-Host 'NInfer 4080 backend not installed, so NInfer is skipped for this run.' -ForegroundColor DarkGray
        Write-Host ''
    }
}
finally{
    Write-Host 'Restoring your original TextGen flags and backend...' -ForegroundColor DarkGray
    try{
        [IO.File]::WriteAllText($flagsFile,$originalFlags,([Text.UTF8Encoding]::new($false)))
        Stop-LocalBackend
        Start-TextGenBackend
        Write-Host 'Original AgentPort/TextGen backend restored.' -ForegroundColor Green
    }catch{
        Write-Warning ('Could not automatically restore the backend: '+$_.Exception.Message)
        Write-Warning 'Your original CMD_FLAGS.txt was restored. Click Apply / Switch in AgentPort to restart TextGen.'
    }
}

Write-Host ''
Write-Host '================ BENCHMARK RESULTS ================' -ForegroundColor Cyan
$results | Sort-Object AverageTokPerSec -Descending | Format-Table Backend,Mode,AverageTokPerSec,MinTokPerSec,MaxTokPerSec,VramMiB,Status -AutoSize
$winner = $results | Where-Object { $_.Status -eq 'OK' -and $_.AverageTokPerSec -gt 0 } | Sort-Object AverageTokPerSec -Descending | Select-Object -First 1
if($winner){
    Write-Host ('WINNER: {0} / {1} at {2:N2} tok/s average' -f $winner.Backend,$winner.Mode,$winner.AverageTokPerSec) -ForegroundColor Green
}else{
    Write-Warning 'No benchmark mode completed successfully.'
}
Write-Host '===================================================' -ForegroundColor Cyan
