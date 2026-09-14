param(
    [int]$FixturePort=0,
    [string]$FixtureToken='',
    [switch]$FixtureNoListener,
    [switch]$KeepScratch
)

$ErrorActionPreference='Stop'
if($FixtureToken){
    $listener=$null
    try {
        if(-not $FixtureNoListener){$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$FixturePort);$listener.Start()}
        while($true){
            if($listener -and $listener.Pending()){$client=$listener.AcceptTcpClient();$client.Close()}
            Start-Sleep -Milliseconds 50
        }
    } finally {if($listener){$listener.Stop()}}
    return
}

. (Join-Path $PSScriptRoot 'AgentPort.Background.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')

function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
function Assert-Alive($Fixture,[string]$Message){Assert-True (Test-AgentPortProcessIdentity $Fixture.Record) $Message}
function Invoke-FixtureStopWorker([object[]]$Plans){
    $payload=[pscustomobject]@{
        PlansJson=(ConvertTo-Json -InputObject @($Plans) -Depth 12 -Compress)
        HelperPath=(Join-Path $PSScriptRoot 'AgentPort.Background.ps1')
        StopModulePath=(Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')
    }
    $worker=@'
param($payload)
$ErrorActionPreference='Stop'
. $payload.HelperPath
. $payload.StopModulePath
$plans=$payload.PlansJson|ConvertFrom-Json
Invoke-AgentPortStopPlansCore $plans
'@
    $operation=New-AgentPortBackgroundOperation -Name 'independent-stop-fixture' -ScriptText $worker -Payload $payload -TimeoutSeconds 20
    try {
        while(-not (Test-AgentPortBackgroundOperationCompleted $operation)){
            if(Test-AgentPortBackgroundOperationTimedOut $operation){throw 'Stop fixture worker timed out.'}
            Start-Sleep -Milliseconds 50
        }
        $result=@(Complete-AgentPortBackgroundOperation $operation)|Where-Object{$_.PSObject.Properties.Name -contains 'StoppedPids'}|Select-Object -Last 1
        Assert-True ($null -ne $result) 'background stop returned a result'
        return $result
    } finally {if($operation.State -eq 'running'){Stop-AgentPortBackgroundOperation $operation}}
}

$scratch=Join-Path $PSScriptRoot ('.stop-core-fixtures-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$fixtures=New-Object System.Collections.Generic.List[object]
function Start-Fixture([string]$Name,[switch]$NoListener){
    $port=0
    if(-not $NoListener){
        $reservation=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
        try{$reservation.Start();$port=[int]$reservation.LocalEndpoint.Port}finally{$reservation.Stop()}
    }
    $arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -FixtureToken "'+$Name+'-'+[guid]::NewGuid().ToString('N')+'" -FixturePort '+$port
    if($NoListener){$arguments+=' -FixtureNoListener'}
    $process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $scratch ($Name+'.out.log')) -RedirectStandardError (Join-Path $scratch ($Name+'.err.log'))
    $fixture=[pscustomobject]@{Process=$process;Record=$null;Port=$port}
    [void]$fixtures.Add($fixture)
    $deadline=(Get-Date).AddSeconds(10)
    do {
        $fixture.Record=Get-AgentPortProcessRecord ([int]$process.Id) $process -ThrowOnQueryFailure
        if($fixture.Record -and ($NoListener -or (Test-AgentPortTcpPortCore $port))){return $fixture}
        if($process.HasExited){throw "Fixture $Name exited before becoming ready."}
        Start-Sleep -Milliseconds 50
    } while((Get-Date) -lt $deadline)
    throw "Fixture $Name did not become ready."
}

try {
    Assert-True ($PSVersionTable.PSVersion.Major -eq 5) 'run this regression under Windows PowerShell 5.1'
    # A sub-millisecond creation time must survive PowerShell 5.1 JSON. Keep
    # all identity fields fixed so this check specifically tests precision.
    $preciseStart=([datetime]'2026-09-01T12:34:56Z').ToUniversalTime().AddTicks(1234)
    $precise=[pscustomobject]@{Pid=1;ParentPid=0;StartTime=$preciseStart;StartTimeUtcTicks=[string]$preciseStart.Ticks;ExecutablePath='C:\fixture\service.exe';CommandLine='service.exe --fixture';Depth=0}
    $roundTrip=$precise|ConvertTo-Json -Depth 4|ConvertFrom-Json
    Assert-True ($roundTrip.StartTime.Ticks -ne $precise.StartTime.Ticks) 'the test exercises the PowerShell 5.1 DateTime precision loss'
    Assert-True (Test-AgentPortProcessIdentity $roundTrip @($precise)) 'the original creation ticks survive JSON exactly'
    $roundTrip.StartTimeUtcTicks=[string]($preciseStart.Ticks+1)
    Assert-True (-not (Test-AgentPortProcessIdentity $roundTrip @($precise))) 'one changed creation tick rejects a reused PID'
    Assert-True (-not (Test-AgentPortProcessIdentity $precise @())) 'an explicit empty process snapshot is authoritative'
    $roundTrip.StartTimeUtcTicks=$precise.StartTimeUtcTicks
    $roundTrip.CommandLine='service.exe --FIXTURE'
    Assert-True (-not (Test-AgentPortProcessIdentity $roundTrip @($precise))) 'command identity comparison preserves argument case'
    $cachedFixtureEntry=ConvertTo-AgentPortStopPath 'C:\fixture\npm-cache\_npx\fixture\node_modules\@deepseek-ai\dsh\lib\bin.js'
    $cachedFixtureRecord=[pscustomobject]@{
        ExecutablePath='C:\nvm4w\nodejs\node.exe'
        CommandLine='"node" "C:\fixture\npm-cache\_npx\fixture\node_modules\.bin\\..\@deepseek-ai\dsh\lib\bin.js" web --no-open'
    }
    Assert-True (Test-AgentPortHarnessCachedRecord $cachedFixtureRecord @($cachedFixtureEntry) '' '') 'the real npm shim doubled-separator path resolves to its owned cached Harness entry'

    $backend=Start-Fixture 'backend-first'
    $harness=Start-Fixture 'harness'
    $foreign=Start-Fixture 'unrelated-listener'
    $backendOwner=$backend.Record|ConvertTo-Json -Depth 6|ConvertFrom-Json
    $backendPlan=Get-AgentPortStopPlan -Kind backend -Port $backend.Port -OwnedProcess $backendOwner
    $foreignPlan=Get-AgentPortStopPlan -Kind harness -Port $foreign.Port -HarnessRoot (Join-Path $scratch 'harness')
    Assert-True (@($foreignPlan.Processes).Count -eq 0) 'a listening port does not confer ownership'
    $backendResult=Invoke-FixtureStopWorker @($backendPlan,$foreignPlan)
    Assert-True (@($backendResult.StoppedPids) -contains $backend.Record.Pid) 'backend stop verifies the owned backend exited'
    Assert-True (@($backendResult.FailedPids).Count -eq 0 -and @($backendResult.RemainingOwnedPids).Count -eq 0) 'backend stop has no hidden failures or surviving owned processes'
    Assert-True (@($backendResult.UnownedListenerPids) -contains $foreign.Record.Pid) 'unrelated listener is reported as unowned'
    Assert-True (@($backendResult.RemainingListenerPids) -contains $foreign.Record.Pid) 'unrelated listener is still listening after backend stop'
    Assert-Alive $harness 'unload model preserves the Harness process'
    Assert-True (Test-AgentPortTcpPortCore $harness.Port) 'Harness stays available after model unload'
    Assert-Alive $foreign 'backend stop preserves the unrelated service'

    $backend=Start-Fixture 'backend-second'
    $harnessOwner=$harness.Record|ConvertTo-Json -Depth 6|ConvertFrom-Json
    $harnessPlan=Get-AgentPortStopPlan -Kind harness -Port $harness.Port -OwnedProcess $harnessOwner
    $harnessResult=Invoke-FixtureStopWorker @($harnessPlan,$foreignPlan)
    Assert-True (@($harnessResult.StoppedPids) -contains $harness.Record.Pid) 'Harness stop verifies the owned Harness exited'
    Assert-True (@($harnessResult.FailedPids).Count -eq 0 -and @($harnessResult.RemainingOwnedPids).Count -eq 0) 'Harness stop has no hidden failures or surviving owned processes'
    Assert-Alive $backend 'stop Harness preserves the backend process'
    Assert-True (Test-AgentPortTcpPortCore $backend.Port) 'backend stays available after Harness stop'
    Assert-Alive $foreign 'Harness stop preserves the unrelated service'

    $stale=$backend.Record|ConvertTo-Json -Depth 6|ConvertFrom-Json
    $stale.StartTimeUtcTicks=[string]([long]$stale.StartTimeUtcTicks+1)
    $stalePlan=[pscustomobject]@{Kind='backend';Port=$backend.Port;Processes=@($stale);UnownedListenerPids=@()}
    $staleResult=Invoke-FixtureStopWorker @($stalePlan)
    Assert-True (@($staleResult.SkippedPids) -contains $backend.Record.Pid) 'a changed identity is skipped immediately before termination'
    Assert-True (@($staleResult.StoppedPids).Count -eq 0) 'a skipped target is never reported as stopped'
    Assert-Alive $backend 'the process with a mismatched identity is left untouched'

    # Use real owned processes without a socket to prove that port closure
    # cannot hide an access-denied error or a process that ignores termination.
    $worker=Start-Fixture 'non-listening-owned' -NoListener
    $workerPlan=Get-AgentPortStopPlan -Kind backend -Port 0 -OwnedProcess $worker.Record
    $denied=& {
        function Stop-Process {param($Id,[switch]$Force,$ErrorAction) throw 'Fixture access denied'}
        Invoke-AgentPortStopPlansCore @($workerPlan)
    }
    Assert-True (@($denied.FailedPids) -contains $worker.Record.Pid) 'termination errors are reported'
    Assert-True (@($denied.RemainingOwnedPids) -contains $worker.Record.Pid) 'a non-listening owned process is still checked after access denied'
    Assert-True (@($denied.StoppedPids).Count -eq 0) 'access denied is not reported as success'
    Assert-True (@($denied.FailureDetails|Where-Object{$_.Message -match 'Fixture access denied'}).Count -eq 1) 'the termination error remains available for the activity log'
    $ignored=& {
        function Stop-Process {param($Id,[switch]$Force,$ErrorAction)}
        Invoke-AgentPortStopPlansCore @($workerPlan)
    }
    Assert-True (@($ignored.FailedPids) -contains $worker.Record.Pid) 'an unsuccessful termination is reported after the bounded exit check'
    Assert-True (@($ignored.RemainingOwnedPids) -contains $worker.Record.Pid -and @($ignored.RemainingListenerPids).Count -eq 0) 'no listener does not imply that an owned process exited'
    Assert-True (@($ignored.StoppedPids).Count -eq 0) 'a returned Stop-Process call alone is not success'
    $queryFailure=& {
        function Get-AgentPortProcessRecord {param($ProcessId,$Process,[switch]$ThrowOnQueryFailure) throw 'Fixture CIM unavailable'}
        Invoke-AgentPortStopPlansCore @($workerPlan)
    }
    Assert-True (@($queryFailure.FailedPids) -contains $worker.Record.Pid -and @($queryFailure.StoppedPids).Count -eq 0) 'an unavailable identity query cannot be mistaken for a process exit'
    $planFailure=& {
        function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) throw 'Fixture process inventory unavailable'}
        try {Get-AgentPortStopPlan -Kind backend -Port 0 -OwnedProcess $worker.Record|Out-Null;return $false}
        catch {return $_.Exception.Message -match 'Fixture process inventory unavailable'}
    }
    Assert-True $planFailure 'an unavailable process inventory cannot produce an empty successful stop plan'
    Assert-Alive $worker 'failure fixtures remain alive for guarded cleanup'
    $syncResult=Stop-AgentPortStopPlan $workerPlan
    Assert-True (@($syncResult.StoppedPids) -contains $worker.Record.Pid -and @($syncResult.RemainingOwnedPids).Count -eq 0) 'the synchronous stop-plan wrapper verifies the same real owned process exit'

    $sibling=[pscustomobject]@{ExecutablePath='C:\AgentPort\llama-b10809-other\llama-server.exe';CommandLine='llama-server.exe --fixture'}
    Assert-True (-not (Test-AgentPortBackendRecord $sibling '' 'C:\AgentPort\llama-b10809')) 'a sibling runtime directory does not confer backend ownership'
    $referenceOnly=[pscustomobject]@{ExecutablePath='C:\unrelated\llama-server.exe';CommandLine='llama-server.exe --model C:\AgentPort\llama-b10809\model.gguf'}
    Assert-True (-not (Test-AgentPortBackendRecord $referenceOnly '' 'C:\AgentPort\llama-b10809')) 'referencing an AgentPort directory does not confer backend ownership'

    Write-Host 'AgentPort independent stop fixtures passed under Windows PowerShell 5.1.' -ForegroundColor Green
    [pscustomobject]@{BackendStopped=@($backendResult.StoppedPids);HarnessStopped=@($harnessResult.StoppedPids);UnrelatedPreserved=$foreign.Record.Pid;DenialReported=@($denied.FailedPids);NonListeningSurvivorReported=@($ignored.RemainingOwnedPids)}|ConvertTo-Json -Compress
} finally {
    foreach($fixture in $fixtures){
        if($fixture.Record -and (Test-AgentPortProcessIdentity $fixture.Record)){
            Microsoft.PowerShell.Management\Stop-Process -Id ([int]$fixture.Record.Pid) -Force -ErrorAction SilentlyContinue
            Microsoft.PowerShell.Management\Wait-Process -Id ([int]$fixture.Record.Pid) -Timeout 5 -ErrorAction SilentlyContinue
        } elseif(-not $fixture.Record){
            # If CIM is unavailable at startup, this exact process handle is
            # still ours. Do not leave a fixture behind while reporting failure.
            try{if(-not $fixture.Process.HasExited){$fixture.Process.Kill();[void]$fixture.Process.WaitForExit(5000)}}catch{}
        }
        $fixture.Process.Dispose()
    }
    $resolvedScratch=[IO.Path]::GetFullPath($scratch)
    $allowedPrefix=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\.stop-core-fixtures-'
    if(-not $KeepScratch -and $resolvedScratch.StartsWith($allowedPrefix,[StringComparison]::OrdinalIgnoreCase)){
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force -ErrorAction Continue
    } else {Write-Host "Scratch retained: $resolvedScratch"}
}
