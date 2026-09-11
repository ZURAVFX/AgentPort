# AgentPort background workers.
#
# This file deliberately contains no WPF references and no access to launcher
# script scope. Workers receive JSON/plain-data snapshots and return plain
# objects. The foreground dispatcher polls the PowerShell async handle rather
# than waiting on it.

function New-AgentPortBackgroundOperation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)]$Payload,
        [int]$TimeoutSeconds=60
    )
    $ps=[System.Management.Automation.PowerShell]::Create()
    try {
        [void]$ps.AddScript($ScriptText).AddArgument($Payload)
        $async=$ps.BeginInvoke()
        return [pscustomobject]@{
            Name=$Name; PowerShell=$ps; AsyncResult=$async; Payload=$Payload
            StartedAt=(Get-Date); TimeoutSeconds=$TimeoutSeconds; State='running'
        }
    } catch {
        $ps.Dispose()
        throw
    }
}

function Test-AgentPortBackgroundOperationCompleted {
    param([Parameter(Mandatory)]$Operation)
    return [bool]$Operation.AsyncResult.IsCompleted
}

function Test-AgentPortBackgroundOperationTimedOut {
    param([Parameter(Mandatory)]$Operation)
    if(Test-AgentPortBackgroundOperationCompleted $Operation){return $false}
    if([int]$Operation.TimeoutSeconds -le 0){return $false}
    return (((Get-Date)-[datetime]$Operation.StartedAt).TotalSeconds -gt [int]$Operation.TimeoutSeconds)
}

function Complete-AgentPortBackgroundOperation {
    param([Parameter(Mandatory)]$Operation)
    if(-not (Test-AgentPortBackgroundOperationCompleted $Operation)){ return $null }
    try {
        $Operation.State='completed'
        return @($Operation.PowerShell.EndInvoke($Operation.AsyncResult))
    } catch {
        $Operation.State='failed'
        throw
    } finally {
        try{$Operation.PowerShell.Dispose()}catch{}
    }
}

function Stop-AgentPortBackgroundOperation {
    param([Parameter(Mandatory)]$Operation)
    try{$Operation.PowerShell.Stop()}catch{}
    try{$Operation.PowerShell.Dispose()}catch{}
    $Operation.State='cancelled'
}

function ConvertTo-AgentPortPathCore {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return ''}
    try { return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) } catch { return '' }
}

function Add-AgentPortModelRootCore {
    param([System.Collections.ArrayList]$Roots,[string]$Path,[string]$Source)
    $full=ConvertTo-AgentPortPathCore $Path
    if(-not $full -or -not [IO.Directory]::Exists($full)){return}
    $key=$full.TrimEnd('\').ToLowerInvariant()
    foreach($existing in @($Roots)){if([string]$existing.Key -eq $key){return}}
    [void]$Roots.Add([pscustomobject]@{Path=$full;Source=$Source;Key=$key})
}

function Read-AgentPortModelDirsCore {
    param([System.Collections.ArrayList]$Roots,[string]$Path,[string]$Source)
    try {
        if(-not [IO.File]::Exists($Path)){return}
        $text=[IO.File]::ReadAllText($Path)
        foreach($match in [regex]::Matches($text,'(?i)"(modelsDirectory|modelDirectory|modelsPath|modelPath|modelDownloadDir|downloadDir)"\s*:\s*"([^"]+)"')){
            $modelPath=$match.Groups[2].Value -replace '\\\\','\'
            Add-AgentPortModelRootCore $Roots $modelPath $Source
        }
    } catch {}
}

function Get-AgentPortModelRootsCore {
    param([Parameter(Mandatory)]$Snapshot)
    $roots=New-Object System.Collections.ArrayList
    Add-AgentPortModelRootCore $roots ([string]$Snapshot.ModelsRoot) 'AgentPort'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.TextGenRoot) 'user_data\models') 'TextGen'
    Add-AgentPortModelRootCore $roots ([string]$Snapshot.OllamaModels) 'Ollama OLLAMA_MODELS'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.UserProfile) '.ollama\models') 'Ollama default'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.UserProfile) '.lmstudio\models') 'LM Studio'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.UserProfile) '.cache\lm-studio\models') 'LM Studio legacy'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.AppData) 'LM Studio') 'LM Studio config'
    Add-AgentPortModelRootCore $roots ([string]$Snapshot.UnslothStudioHome) 'Unsloth Studio'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.UserProfile) '.unsloth') 'Unsloth Studio'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.LocalAppData) 'Unsloth Studio') 'Unsloth Studio'
    Add-AgentPortModelRootCore $roots ([string]$Snapshot.HfHubCache) 'Hugging Face cache'
    if($Snapshot.HfHome){Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.HfHome) 'hub') 'Hugging Face HF_HOME'}
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.UserProfile) '.cache\huggingface\hub') 'Hugging Face default'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.AppData) 'Jan\models') 'Jan'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.LocalAppData) 'Jan\models') 'Jan'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.LocalAppData) 'nomic.ai\GPT4All') 'GPT4All'
    Add-AgentPortModelRootCore $roots (Join-Path ([string]$Snapshot.AppData) 'nomic.ai\GPT4All') 'GPT4All'
    foreach($cfg in @((Join-Path ([string]$Snapshot.AppData) 'LM Studio'),(Join-Path ([string]$Snapshot.LocalAppData) 'LM Studio'),(Join-Path ([string]$Snapshot.AppData) 'Jan'),(Join-Path ([string]$Snapshot.LocalAppData) 'Jan'))){
        if([IO.Directory]::Exists($cfg)){
            try {
                Get-ChildItem -LiteralPath $cfg -Include *.json,*.jsonc -Recurse -File -ErrorAction SilentlyContinue |
                    Select-Object -First 60 |
                    ForEach-Object {Read-AgentPortModelDirsCore $roots $_.FullName ((Split-Path $cfg -Leaf)+' custom path')}
            } catch {}
        }
    }
    return @($roots)
}

function Find-AgentPortRelatedMmprojCore {
    param([string]$ModelPath,$Helpers)
    foreach($binding in @($Helpers)){
        if([string]$binding.model -eq $ModelPath -and $binding.helper -and [IO.File]::Exists([string]$binding.helper)){return @([string]$binding.helper)}
    }
    $dir=Split-Path $ModelPath -Parent
    if(-not [IO.Directory]::Exists($dir)){return @()}
    $projectors=@(Get-ChildItem -LiteralPath $dir -Filter 'mmproj*.gguf' -File -ErrorAction SilentlyContinue)
    if($projectors.Count -eq 0){$projectors=@(Get-ChildItem -LiteralPath $dir -Filter '*mmproj*.gguf' -File -ErrorAction SilentlyContinue)}
    if($projectors.Count -eq 0){return @()}
    $stem=[IO.Path]::GetFileNameWithoutExtension($ModelPath) -replace '(?i)[-_.](?:UD-)?(?:IQ\d|Q\d|BF16|F16|FP16|\d+(?:\.\d+)?bpw).*$',''
    $key=($stem -replace '[^A-Za-z0-9]','').ToLowerInvariant()
    $matched=@($projectors | Where-Object {
        $helperStem=([IO.Path]::GetFileNameWithoutExtension($_.Name) -replace '^(?i)mmproj[-_.]*','' -replace '(?i)[-_.](?:BF16|F16|FP16|Q\d).*$','')
        $helperKey=($helperStem -replace '[^A-Za-z0-9]','').ToLowerInvariant()
        $helperKey.Length -ge 5 -and ($key.Contains($helperKey) -or $helperKey.Contains($key))
    })
    if($matched.Count -gt 0){return @($matched|Select-Object -ExpandProperty FullName)}
    $models=@(Get-ChildItem -LiteralPath $dir -Filter '*.gguf' -File -ErrorAction SilentlyContinue|Where-Object{$_.Name -notmatch '(?i)mmproj'})
    if($projectors.Count -eq 1 -and $models.Count -eq 1){return @($projectors[0].FullName)}
    return @()
}

function Get-AgentPortModelCatalogueCore {
    param([Parameter(Mandatory)]$Snapshot)
    $roots=Get-AgentPortModelRootsCore $Snapshot
    $items=@()
    foreach($fixed in @($Snapshot.BuiltinModels)){
        if($fixed){$items+=[pscustomobject]$fixed}
    }
    $seen=@{}
    $ignored=@($Snapshot.IgnoredModels|ForEach-Object{[string]$_})
    $deadline=(Get-Date).AddSeconds([math]::Max(5,[int]$Snapshot.ScanBudgetSeconds))
    foreach($rootInfo in $roots){
        if((Get-Date) -gt $deadline){break}
        $root=[string]$rootInfo.Path
        try {
            Get-ChildItem -LiteralPath $root -Filter '*.gguf' -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '^(?i:mmproj)' -and $_.Name -notmatch '(?i)mmproj.*\.gguf$' } |
                Select-Object -First 800 |
                ForEach-Object {
                    if((Get-Date) -gt $deadline){throw 'model scan budget exceeded'}
                    $size=[double]$_.Length
                    if($size -le 0){
                        $target=''
                        if($_.PSObject.Properties.Name -contains 'ResolvedTarget' -and $_.ResolvedTarget){$target=[string]$_.ResolvedTarget}
                        elseif($_.PSObject.Properties.Name -contains 'Target' -and $_.Target){try{$target=[IO.Path]::GetFullPath((Join-Path $_.DirectoryName ([string]$_.Target)))}catch{}}
                        if($target -and [IO.File]::Exists($target)){try{$size=[double](Get-Item -LiteralPath $target -Force).Length}catch{}}
                    }
                    if($size -lt [double]$Snapshot.MinimumModelBytes){return}
                    $key=$_.FullName.ToLowerInvariant()
                    if($seen.ContainsKey($key) -or $ignored -contains $_.FullName){return}
                    $seen[$key]=$true
                    try{$rel=$_.FullName.Substring($root.TrimEnd('\').Length).TrimStart('\').Replace('\','/')}catch{$rel=$_.Name}
                    $mainRoot=($root.TrimEnd('\').ToLowerInvariant() -eq ([string]$Snapshot.ModelsRoot).TrimEnd('\').ToLowerInvariant())
                    $modelId=if($mainRoot){$rel}else{$_.FullName}
                    $helpers=Find-AgentPortRelatedMmprojCore $_.FullName $Snapshot.ModelHelpers
                    $helperText=if($helpers.Count -gt 0){' | helper: '+[IO.Path]::GetFileName($helpers[0])}else{''}
                    $source=[string]$rootInfo.Source
                    if($_.FullName -match '(?i)\\models--unsloth--'){$source='Unsloth Desktop'}
                    $items+=[pscustomobject]@{
                        Display=('{0} | {1:N2} GB | {2}{3}' -f $_.Name,($size/1GB),$source,$helperText)
                        Name=$_.Name; RelPath=$modelId; FullPath=$_.FullName; Source=$source; RootPath=$root
                        HelperFiles=@($helpers); SizeBytes=$size; SizeGB=[math]::Round(($size/1GB),2); Installed=$true
                    }
                }
        } catch { if($_.Exception.Message -notmatch 'model scan budget exceeded'){} }
    }
    $sorted=@($items|Sort-Object @{Expression={if($_.Source -eq 'Team'){0}elseif($_.Source -eq 'NInfer'){2}else{1}}},Name)
    return [pscustomobject]@{Models=$sorted;Roots=$roots;ScannedAt=(Get-Date).ToString('o');TimedOut=((Get-Date)-gt $deadline)}
}

function Test-AgentPortTcpPortCore {
    param([int]$Port,[int]$TimeoutMilliseconds=250)
    $client=New-Object System.Net.Sockets.TcpClient
    try {
        $async=$client.BeginConnect('127.0.0.1',$Port,$null,$null)
        if(-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)){return $false}
        $client.EndConnect($async);return $true
    } catch {return $false} finally {$client.Close()}
}

function Get-AgentPortLoadedModelCore {
    if(-not (Test-AgentPortTcpPortCore 5100 200)){return ''}
    try {
        $r=Invoke-RestMethod -Uri 'http://127.0.0.1:5100/v1/internal/model/info' -Method Get -Headers @{Authorization='Bearer local-textgen';Accept='application/json'} -TimeoutSec 1 -ErrorAction Stop
        if($r.model_name -and [string]$r.model_name -notin @('none','null')){return [string]$r.model_name}
    } catch {}
    try {
        $r=Invoke-RestMethod -Uri 'http://127.0.0.1:5100/v1/models' -Method Get -Headers @{Authorization='Bearer local-textgen';Accept='application/json'} -TimeoutSec 1 -ErrorAction Stop
        if($r.data -and @($r.data).Count -gt 0){return [string]$r.data[0].id}
    } catch {}
    return ''
}

function Get-AgentPortMetricsCore {
    param([bool]$Enabled)
    if(-not $Enabled -or -not (Test-AgentPortTcpPortCore 5100 200)){return [pscustomobject]@{Available=$false;Rate=0;Prompt=0;Cached=0;Generated=0;Active=0}}
    try {
        $text=(Invoke-WebRequest -Uri 'http://127.0.0.1:5100/metrics' -Headers @{Authorization='Bearer local-textgen'} -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop).Content
        $values=@{}
        foreach($match in [regex]::Matches($text,'(?m)^llamacpp:([a-z_]+)\s+([0-9.eE+-]+)\s*$')){$values[$match.Groups[1].Value]=[double]::Parse($match.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)}
        return [pscustomobject]@{Available=$true;Rate=if($values.tokens_predicted_seconds_total -gt 0){$values.tokens_predicted_total/$values.tokens_predicted_seconds_total}else{0};Prompt=$values.prompt_tokens_total;Cached=$values.prompt_tokens_cached_total;Generated=$values.tokens_predicted_total;Active=$values.requests_processing}
    } catch {return [pscustomobject]@{Available=$false;Rate=0;Prompt=0;Cached=0;Generated=0;Active=0}}
}

function Get-AgentPortRuntimeSnapshotCore {
    param([Parameter(Mandatory)]$Snapshot)
    $backend=Test-AgentPortTcpPortCore 5100 250
    $harness=Test-AgentPortTcpPortCore 3080 250
    $loaded=if($backend){Get-AgentPortLoadedModelCore}else{''}
    $metrics=Get-AgentPortMetricsCore ([bool]$Snapshot.MetricsEnabled)
    $gpu=[pscustomobject]@{Name='NVIDIA GPU';Total=0;Free=0;Used=0}
    try {
        $line=& nvidia-smi --query-gpu=name,memory.used,memory.total,memory.free --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if($line){$p=$line -split ','|ForEach-Object{$_.Trim()};$gpu=[pscustomobject]@{Name=$p[0];Used=[math]::Round(([double]$p[1]/1024),1);Total=[math]::Round(([double]$p[2]/1024),1);Free=[math]::Round(([double]$p[3]/1024),1)}}
    } catch {}
    $ram=[pscustomobject]@{Used=0;Total=0}
    try {$os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$total=[double]$os.TotalVisibleMemorySize/1MB;$ram=[pscustomobject]@{Used=($total-([double]$os.FreePhysicalMemory/1MB));Total=$total}}catch{}
    return [pscustomobject]@{
        CapturedAt=(Get-Date).ToString('o');BackendOnline=$backend;HarnessOnline=$harness;LoadedModel=$loaded;Metrics=$metrics;Gpu=$gpu;Ram=$ram
        Install=$Snapshot.Install;StopGeneration=[int]$Snapshot.StopGeneration
    }
}

function Invoke-AgentPortExternalCommandCore {
    param([Parameter(Mandatory)]$Payload)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=[string]$Payload.FilePath
    $psi.Arguments=[string]$Payload.Arguments
    $psi.WorkingDirectory=[string]$Payload.WorkingDirectory
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    if($Payload.StdOut){$psi.RedirectStandardOutput=$true};if($Payload.StdErr){$psi.RedirectStandardError=$true}
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    if(-not $p.Start()){throw 'Could not start background command.'}
    $stdoutTask=$null;$stderrTask=$null
    if($Payload.StdOut){$stdoutTask=$p.StandardOutput.ReadToEndAsync()}
    if($Payload.StdErr){$stderrTask=$p.StandardError.ReadToEndAsync()}
    $timeout=[math]::Max(1,[int]$Payload.TimeoutSeconds)*1000
    $exited=$p.WaitForExit($timeout)
    if(-not $exited){try{$p.Kill()}catch{};try{$p.WaitForExit(2000)}catch{};return [pscustomobject]@{ExitCode=-1;TimedOut=$true;StdOut=if($stdoutTask){$stdoutTask.Result}else{''};StdErr=if($stderrTask){$stderrTask.Result}else{''}} }
    # Drain tasks that were started before WaitForExit so a verbose child
    # cannot deadlock the worker on a full redirected pipe.
    $stdout=if($stdoutTask){$stdoutTask.Result}else{''}
    $stderr=if($stderrTask){$stderrTask.Result}else{''}
    return [pscustomobject]@{ExitCode=$p.ExitCode;TimedOut=$false;StdOut=$stdout;StdErr=$stderr}
}

function Invoke-AgentPortStopPlansCore {
    param([Parameter(Mandatory)]$Plans)
    $stopped=New-Object System.Collections.Generic.List[int]
    $skipped=New-Object System.Collections.Generic.List[int]
    $unowned=New-Object System.Collections.Generic.List[int]
    foreach($plan in @($Plans)){
        foreach($listenerPid in @($plan.UnownedListenerPids)){if([int]$listenerPid -gt 0){[void]$unowned.Add([int]$listenerPid)}}
        foreach($expected in @($plan.Processes|Sort-Object @{Expression={$_.Depth};Descending=$true},Pid)){
            $targetPid=[int]$expected.Pid
            try{$current=Get-CimInstance Win32_Process -Filter "ProcessId=$targetPid" -ErrorAction Stop}catch{$current=$null}
            if(-not $current){continue}
            $startExpected=$null;$startCurrent=$null
            try{$startExpected=[Management.ManagementDateTimeConverter]::ToDateTime([string]$expected.StartTime).ToUniversalTime()}catch{try{$startExpected=([datetime]$expected.StartTime).ToUniversalTime()}catch{}}
            try{$startCurrent=[Management.ManagementDateTimeConverter]::ToDateTime([string]$current.CreationDate).ToUniversalTime()}catch{try{$startCurrent=([datetime]$current.CreationDate).ToUniversalTime()}catch{}}
            $sameStart=$startExpected -and $startCurrent -and $startExpected.Ticks -eq $startCurrent.Ticks
            $samePath=([string]$expected.ExecutablePath -eq [string]$current.ExecutablePath)
            $sameCommand=([string]$expected.CommandLine -eq [string]$current.CommandLine)
            if(-not ($sameStart -and $samePath -and $sameCommand)){[void]$skipped.Add($targetPid);continue}
            try{Stop-Process -Id $targetPid -Force -ErrorAction Stop;[void]$stopped.Add($targetPid)}catch{}
        }
    }
    # A stop is not successful merely because Stop-Process returned. Give owned
    # listeners a bounded window to close, then report every port still in use.
    $remaining=New-Object System.Collections.Generic.List[int]
    $ports=@($Plans|ForEach-Object{[int]$_.Port}|Where-Object{$_ -gt 0}|Select-Object -Unique)
    $deadline=(Get-Date).AddSeconds(5)
    do {
        $remaining.Clear()
        foreach($port in $ports){
            foreach($line in @(& netstat.exe -ano -p TCP 2>$null)){
                if($line -match ('^\s*TCP\s+\S+:'+([regex]::Escape([string]$port))+'\s+\S+\s+LISTENING\s+(\d+)\s*$')){[void]$remaining.Add([int]$Matches[1])}
            }
        }
        if($remaining.Count -eq 0 -or $stopped.Count -eq 0){break}
        Start-Sleep -Milliseconds 100
    } while((Get-Date) -lt $deadline)
    return [pscustomobject]@{
        StoppedPids=$stopped.ToArray();SkippedPids=$skipped.ToArray()
        UnownedListenerPids=@($unowned.ToArray()|Select-Object -Unique)
        RemainingListenerPids=@($remaining.ToArray()|Select-Object -Unique)
        CompletedAt=(Get-Date).ToString('o')
    }
}
