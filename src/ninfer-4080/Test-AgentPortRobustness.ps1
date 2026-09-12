param([switch]$KeepScratch)

$ErrorActionPreference='Stop'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('AgentPort-robustness-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    . (Join-Path $PSScriptRoot 'AgentPort.Background.ps1')
    . (Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')

    function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
    function New-Record([int]$ProcessId,[int]$ParentPid,[datetime]$Start,[string]$Exe,[string]$Command,[int]$Depth=0){
        [pscustomobject]@{Pid=$ProcessId;ParentPid=$ParentPid;StartTime=$Start;ExecutablePath=$Exe;CommandLine=$Command;Depth=$Depth}
    }

    $cache=Join-Path $scratch 'npm-cache'
    $entryDir=Join-Path $cache '_npx\fixture\node_modules\@deepseek-ai\dsh'
    New-Item -ItemType Directory -Force -Path (Join-Path $entryDir 'lib') | Out-Null
    Set-Content -LiteralPath (Join-Path $entryDir 'package.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $entryDir 'lib\bin.js') -Value 'fixture'
    $entry=(Join-Path $entryDir 'lib\bin.js')
    $nodeExe='C:\nvm4w\nodejs\node.exe'
    $otherExe='C:\Program Files\Adobe\node.exe'
    $start=(Get-Date).ToUniversalTime()
    $wrapper=New-Record 100 1 $start 'C:\Windows\System32\cmd.exe' ('cmd.exe /c npx --cache "'+$cache+'" @deepseek-ai/dsh@latest web')
    $cached=New-Record 101 100 $start $nodeExe ('"'+$nodeExe+'" "'+$entry+'" web --no-open') 1
    $unrelated=New-Record 102 1 $start $otherExe ('"'+$otherExe+'" unrelated-web-server --port 3080')
    $records=@($wrapper,$cached,$unrelated)

    $plan=Get-AgentPortStopPlan -Kind harness -Port 3080 -OwnedProcess $wrapper -ProcessRecords $records -ListenerPids @(101,102) -HarnessRoot (Join-Path $scratch 'harness') -NpmCacheRoot $cache -PortableNodeDir (Join-Path $scratch 'portable-node')
    $targetPids=@($plan.Processes|ForEach-Object{$_.Pid})
    Assert-True ($targetPids -contains 100) 'owned wrapper is captured'
    Assert-True ($targetPids -contains 101) 'cached child is captured before wrapper termination'
    Assert-True ($targetPids -notcontains 102) 'unrelated Node listener is not captured'
    Assert-True (@($plan.UnownedListenerPids) -contains 102) 'unrelated listener is reported, not killed'

    $orphanPlan=Get-AgentPortStopPlan -Kind harness -Port 3080 -ProcessRecords @($cached,$unrelated) -ListenerPids @(101,102) -HarnessRoot (Join-Path $scratch 'harness') -NpmCacheRoot $cache -PortableNodeDir (Join-Path $scratch 'portable-node')
    Assert-True (@($orphanPlan.Processes|ForEach-Object{$_.Pid}) -contains 101) 'orphan cached dsh entry is recovered through system Node'
    Assert-True (@($orphanPlan.Processes|ForEach-Object{$_.Pid}) -notcontains 102) 'orphan unrelated Node is preserved'

    $reused=New-Record 100 1 $start.AddSeconds(5) $otherExe ('"'+$otherExe+'" unrelated-web-server --port 3080')
    $reusePlan=Get-AgentPortStopPlan -Kind harness -Port 3080 -OwnedProcess $wrapper -ProcessRecords @($reused) -ListenerPids @(100) -HarnessRoot (Join-Path $scratch 'harness') -NpmCacheRoot $cache -PortableNodeDir (Join-Path $scratch 'portable-node')
    Assert-True (@($reusePlan.Processes).Count -eq 0) 'PID reuse fails the exact start/path/command guard'
    Assert-True (@($reusePlan.UnownedListenerPids) -contains 100) 'PID-reused listener remains unowned'

    $modelRoot=Join-Path $scratch 'models';New-Item -ItemType Directory -Force -Path $modelRoot | Out-Null
    $modelPath=Join-Path $modelRoot 'fixture.gguf';Set-Content -LiteralPath $modelPath -Value ('x'*128)
    $scanSnapshot=[ordered]@{
        ModelsRoot=$modelRoot;TextGenRoot=(Join-Path $scratch 'textgen');UserProfile=$scratch;AppData=$scratch;LocalAppData=$scratch
        OllamaModels='';UnslothStudioHome='';HfHubCache='';HfHome='';IgnoredModels=@();ModelHelpers=@();BuiltinModels=@()
        MinimumModelBytes=1;ScanBudgetSeconds=10
    }
    $payload=[pscustomobject]@{SnapshotJson=($scanSnapshot|ConvertTo-Json -Depth 12);HelperPath=(Join-Path $PSScriptRoot 'AgentPort.Background.ps1')}
    $worker=@'
param($payload)
. $payload.HelperPath
$snapshot=$payload.SnapshotJson|ConvertFrom-Json
Get-AgentPortModelCatalogueCore $snapshot
'@
    $op=New-AgentPortBackgroundOperation -Name 'fixture-scan' -ScriptText $worker -Payload $payload -TimeoutSeconds 10
    while(-not (Test-AgentPortBackgroundOperationCompleted $op)){Start-Sleep -Milliseconds 25}
    $scan=@(Complete-AgentPortBackgroundOperation $op)|Where-Object{$_.Models}|Select-Object -Last 1
    Assert-True (@($scan.Models|Where-Object{$_.FullPath -eq $modelPath}).Count -eq 1) 'background scan returns the local model as plain data'

    Write-Host 'AgentPort robustness fixture passed.' -ForegroundColor Green
} finally {
    if(-not $KeepScratch){Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue}else{Write-Host "Scratch retained: $scratch"}
}
