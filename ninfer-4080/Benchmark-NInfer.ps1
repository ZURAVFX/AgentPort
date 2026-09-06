[CmdletBinding()]
param([int]$Context=24576,[int]$MaxTokens=256,[string]$Distro='Ubuntu-24.04',
      [int[]]$Drafts=@(3),[int]$Port=5101,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'results'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$prompts=@(
 'Write a concise Python implementation of an async retry helper with exponential backoff, jitter, cancellation support, type hints, and one short usage example.',
 'Write a TypeScript function that merges two arrays of records by id, keeps the newest updatedAt value, preserves stable ordering, and explain the complexity briefly.',
 'Write a PowerShell function that checks whether a TCP port is listening, returns the owning process name when available, and handles access errors cleanly.',
 'Return exactly 12 JSON objects for a coding-agent file plan. Keys: action,path,operation,reason,verify. Use a Python REST API project. No prose outside the JSON array.',
 'Return exactly 12 JSON objects for a coding-agent file plan. Keys: action,path,operation,reason,verify. Use a TypeScript desktop app project. No prose outside the JSON array.',
 'Return exactly 12 JSON objects for a coding-agent file plan. Keys: action,path,operation,reason,verify. Use a Windows PowerShell launcher project. No prose outside the JSON array.'
)
$rows=[Collections.Generic.List[object]]::new()
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$csv=Join-Path $OutputDirectory "benchmark-$stamp.csv"
Write-Host "NInfer-only benchmark | stock Qwen3.8-27B min-Q4 (NOT Ridge) | context $Context | INT4 KV | cap $MaxTokens"
Write-Host 'Rates include prompt processing and HTTP overhead; completion tokens include reasoning. TextGen is not restarted or retested.'
foreach($draft in $Drafts){
    $state=$null
    try {
        $state=Start-NInferService -Distro $Distro -Context $Context -Draft $draft -Port $Port -LogDirectory (Join-Path $OutputDirectory "logs-$stamp-mtp$draft")
        $headers=@{Authorization='Bearer local-textgen'}
        $warm=@{model=$state.Model;messages=@(@{role='user';content='Reply READY only.'});max_tokens=16;temperature=0;stream=$false}|ConvertTo-Json -Depth 8
        $null=Invoke-RestMethod ($state.BaseUrl+'/chat/completions') -Method Post -Headers $headers -ContentType 'application/json' -Body $warm -TimeoutSec 120
        for($i=0;$i -lt $prompts.Count;$i++){
            $body=@{model=$state.Model;messages=@(@{role='user';content=$prompts[$i]});max_tokens=$MaxTokens;temperature=0;stream=$false}|ConvertTo-Json -Depth 8
            $timer=[Diagnostics.Stopwatch]::StartNew()
            $response=Invoke-RestMethod ($state.BaseUrl+'/chat/completions') -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 180
            $timer.Stop()
            if($response.model -ne $state.Model -or -not $response.usage.completion_tokens){throw 'Invalid completion identity or missing token usage.'}
            $tokens=[int]$response.usage.completion_tokens
            $suite=if($i -lt 3){'Fresh'}else{'RepetitiveAgent'}
            $row=[pscustomobject]@{Backend='NInfer';Model=$state.Model;Draft=$draft;Context=$Context;Suite=$suite;Task=$i%3+1;Tokens=$tokens;Seconds=$timer.Elapsed.TotalSeconds;TokPerSec=$tokens/$timer.Elapsed.TotalSeconds}
            $rows.Add($row)
            $rows | Export-Csv -LiteralPath $csv -NoTypeInformation
            $response | ConvertTo-Json -Depth 30 | Out-File (Join-Path $OutputDirectory "$stamp-mtp$draft-task$i.json") -Encoding utf8
            Write-Host ('MTP{0} / {1} / {2}: {3:N2} tok/s ({4} tokens)' -f $draft,$suite,$row.Task,$row.TokPerSec,$tokens)
        }
    } finally {if($state){Stop-NInferService $state}}
}
$summary=@($rows | Group-Object Draft | ForEach-Object {
    $tokens=($_.Group | Measure-Object Tokens -Sum).Sum
    $seconds=($_.Group | Measure-Object Seconds -Sum).Sum
    [pscustomobject]@{Draft=[int]$_.Name;WeightedTokPerSec=[math]::Round($tokens/$seconds,2);Tokens=$tokens;Context=$Context}
})
$summary | Sort-Object WeightedTokPerSec -Descending | Format-Table
$summary | Export-Csv (Join-Path $OutputDirectory "summary-$stamp.csv") -NoTypeInformation
Write-Host "Saved results: $csv"
