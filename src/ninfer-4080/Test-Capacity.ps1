param([int[]]$Contexts=@(49152,65536,98304),[int]$Prefill=64)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
$results=@()
foreach($ctx in $Contexts){
    $state=$null
    try {
        $state=Start-NInferService -Context $ctx -Prefill $Prefill -Port 5101 -LogDirectory (Join-Path $PSScriptRoot "results\capacity-$ctx-$Prefill")
        $body=@{model=$state.Model;messages=@(@{role='user';content='Explain how a binary search works.'});max_tokens=256;temperature=0;stream=$false}|ConvertTo-Json -Depth 5
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $reply=Invoke-RestMethod ($state.BaseUrl+'/chat/completions') -Headers @{Authorization='Bearer local-textgen'} -ContentType application/json -Method Post -Body $body -TimeoutSec 120
        $timer.Stop()
        $memory=(Get-Content -LiteralPath $state.Out,$state.Err | Select-String 'free-after-startup=' | Select-Object -Last 1).Line
        $results+=[pscustomobject]@{Context=$ctx;Prefill=$Prefill;Success=$true;TokPerSec=$reply.usage.completion_tokens/$timer.Elapsed.TotalSeconds;Memory=$memory}
    } catch {$results+=[pscustomobject]@{Context=$ctx;Prefill=$Prefill;Success=$false;TokPerSec=0;Memory=$_.Exception.Message}}
    finally {if($state){Stop-NInferService $state}}
    $results | Export-Csv (Join-Path $PSScriptRoot "results\capacity-$Prefill.csv") -NoTypeInformation
    $results[-1] | Format-List
}
