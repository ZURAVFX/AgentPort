[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$src = [IO.File]::ReadAllText((Resolve-Path $InputPath))

function Replace-Required([string]$Needle,[string]$Replacement,[string]$Label) {
    if (-not $script:src.Contains($Needle)) { throw "Patch anchor not found: $Label" }
    $script:src = $script:src.Replace($Needle,$Replacement)
}

# Surface the experimental backend in the app version without maintaining a second 270 KB source copy.
$src = $src.Replace("1.6.2","1.7.0-4080")

$helpers = @'
# --- AgentPort RTX 4080/NInfer backend ---------------------------------------
function Get-AgentPortRuntimeBackend {
    if($script:Config -and $script:Config.PSObject.Properties.Name -contains 'runtime_backend'){
        $v=[string]$script:Config.runtime_backend
        if($v){ return $v }
    }
    return 'Auto'
}

function Get-AgentPortNInferDistro {
    if($script:Config -and $script:Config.PSObject.Properties.Name -contains 'ninfer_wsl_distro'){
        $v=[string]$script:Config.ninfer_wsl_distro
        if($v){ return $v }
    }
    return 'Ubuntu-24.04'
}

function Test-AgentPortRtx4080 {
    try{
        $name = (& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1)
        return ([string]$name -match 'RTX 4080')
    }catch{ return $false }
}

function Test-AgentPortNInferWslReady {
    param([string]$Distro)
    try{
        & wsl.exe -d $Distro -- bash -lc "test -x ~/.agentport/ninfer-src/build-sm89/apps/ninfer-serve -a -s ~/.agentport/models/qwen3_8_27b_minq4.ninfer" 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    }catch{ return $false }
}

function Start-AgentPortNInfer4080IfEligible {
    param([string]$Model,[int]$Context)
    $backend = Get-AgentPortRuntimeBackend
    if($backend -eq 'TextGen'){ return $false }

    # NInfer is checkpoint-specific. Only substitute the known Ridge quant of stock
    # Qwen3.8-27B. A differently named GGUF might be a finetune or merge and must not
    # silently be replaced by the stock NInfer artifact.
    $eligible = ([string]$Model -match '(?i)Qwen3\.8-27B-Ridge-3\.7bpw\.gguf$')
    if(-not $eligible){
        if($backend -eq 'NInfer4080'){
            Set-Log 'NInfer4080 currently supports Qwen3.8-27B-Ridge-3.7bpw.gguf only; using TextGen for the selected model.' 'warn'
        }
        return $false
    }

    if(-not (Test-AgentPortRtx4080)){
        if($backend -eq 'NInfer4080'){ Set-Log 'NInfer4080 requested but no RTX 4080-class GPU was detected; falling back to TextGen.' 'warn' }
        return $false
    }

    $distro = Get-AgentPortNInferDistro
    if(-not (Test-AgentPortNInferWslReady $distro)){
        if($backend -eq 'NInfer4080'){ Set-Log ('NInfer4080 requested but the WSL engine/model is not installed in '+$distro+'; falling back to TextGen.') 'warn' }
        return $false
    }

    # The published 16 GB fork is measured at 49k with MTP3 and supports longer contexts.
    # Clamp the GUI request to a conservative 98k ceiling on a 16 GB 4080.
    $ctx = [Math]::Max(8192,[Math]::Min([int]$Context,98304))
    $modelId = ([string]$Model).Replace("'",'')
    $cmd = "pkill -f 'ninfer-serve.*--port 5100' >/dev/null 2>&1 || true; mkdir -p ~/.agentport/logs; nohup ~/.agentport/ninfer-src/build-sm89/apps/ninfer-serve ~/.agentport/models/qwen3_8_27b_minq4.ninfer --host 0.0.0.0 --port 5100 --api-key local-textgen --model-id '$modelId' --max-context $ctx --kv-capacity $ctx --max-concurrency 1 --prefill-chunk 64 --kv-dtype i4 --spec mtp --draft-tokens 3 --lm-head-draft --preserve-thinking > ~/.agentport/logs/ninfer-serve.log 2>&1 < /dev/null &"
    try{
        & wsl.exe -d $distro -- bash -lc $cmd | Out-Null
        if($LASTEXITCODE -ne 0){ throw "wsl exit $LASTEXITCODE" }
        Set-Log ('Starting NInfer RTX 4080 backend: '+$ctx+' ctx, INT4 KV, native MTP3.') 'ok'
        $script:TextGenProcess = $null
        return $true
    }catch{
        Set-Log ('NInfer4080 launch failed; falling back to TextGen. '+$_.Exception.Message) 'warn'
        return $false
    }
}
# -----------------------------------------------------------------------------

'@

Replace-Required "function Start-TextGen {" ($helpers + "function Start-TextGen {`r`n    if(Start-AgentPortNInfer4080IfEligible -Model ([string]`$script:PendingModel) -Context ([int]`$script:PendingContext)){ return }") 'Start-TextGen injection'

$oldSpec = @'
    # Model-agnostic speculative decoding. ngram-mod works without requiring an MTP-specific GGUF.
    switch($SpecMode){
        'Conservative' { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 16'; $lines += '--spec-ngram-size-m 32' }
        'Medium'       { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 24'; $lines += '--spec-ngram-size-m 48' }
        'Aggressive'   { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 32'; $lines += '--spec-ngram-size-m 64' }
    }
'@

$newSpec = @'
    # Qwen3.8 Ridge retains the model's native MTP head. Prefer real MTP over generic n-gram
    # speculation. Keep the modes as MTP-only because combined speculative modes have shown
    # recent regressions on Qwen3.8's hybrid architecture.
    $isQwen38Mtp = ([string]$Model -match '(?i)Qwen3\.8-27B.*\.gguf$')
    if($isQwen38Mtp -and $SpecMode -ne 'Off'){
        switch($SpecMode){
            'Conservative' { $lines += '--spec-type draft-mtp'; $lines += '--spec-draft-n-max 2' }
            'Medium'       { $lines += '--spec-type draft-mtp'; $lines += '--spec-draft-n-max 4' }
            'Aggressive'   { $lines += '--spec-type draft-mtp'; $lines += '--spec-draft-n-max 6' }
        }
    } else {
        switch($SpecMode){
            'Conservative' { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 16'; $lines += '--spec-ngram-size-m 32' }
            'Medium'       { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 24'; $lines += '--spec-ngram-size-m 48' }
            'Aggressive'   { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 32'; $lines += '--spec-ngram-size-m 64' }
        }
    }
'@
Replace-Required $oldSpec $newSpec 'native MTP flags'

$outDir = Split-Path -Parent $OutputPath
if($outDir -and -not (Test-Path $outDir)){ New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
[IO.File]::WriteAllText($OutputPath,$src,([Text.UTF8Encoding]::new($false)))

# PowerShell parse validation catches malformed generated source in CI before packaging.
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($OutputPath,[ref]$tokens,[ref]$errors) | Out-Null
if($errors.Count -gt 0){
    $msg=($errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n"
    throw "Generated AgentPort runtime is not valid PowerShell:`n$msg"
}
Write-Host "Patched runtime written to $OutputPath"
