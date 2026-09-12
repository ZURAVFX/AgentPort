param([Parameter(Mandatory)][string]$StartupUrl,[Parameter(Mandatory)][string]$ExpectedModel)
$ErrorActionPreference='Stop'
$base='http://127.0.0.1:3080'
$null=Invoke-WebRequest $StartupUrl -UseBasicParsing -SessionVariable browserSession -TimeoutSec 10
function Invoke-HarnessTestRpc([string]$Method,[hashtable]$Arguments){
    $body=@{type='client-request';rpcId=[guid]::NewGuid().ToString();method=$Method;payload=@{args=$Arguments}} | ConvertTo-Json -Depth 20 -Compress
    $reply=Invoke-RestMethod ($base+'/api/'+$Method) -WebSession $browserSession -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 15
    if(-not $reply.result.ok){throw ('Harness '+$Method+': '+$reply.result.error.message)}
    return $reply.result.value
}
$session=Invoke-HarnessTestRpc 'session/create' @{request=@{}}
function Find-AssistantMessages($Value){
    if($null -eq $Value -or $Value -is [string]){return}
    if($Value.role -eq 'assistant'){ $Value; return }
    if($Value -is [System.Array]){foreach($v in $Value){Find-AssistantMessages $v};return}
    if($Value -is [pscustomobject]){foreach($p in $Value.PSObject.Properties){Find-AssistantMessages $p.Value}}
}
$sessionId=$session.sessionId
Invoke-HarnessTestRpc 'session/rename' @{request=@{sessionId=$sessionId;title='AgentPort startup verification'}} | Out-Null
Invoke-HarnessTestRpc 'session/prompt' @{request=@{sessionId=$sessionId;requestId=[guid]::NewGuid().ToString();mode='queue';content=@(@{type='text';text='Reply with only READY. Do not use any tools.'})}} | Out-Null
$deadline=(Get-Date).AddSeconds(120)
do {
    Start-Sleep -Seconds 2
    $list=Invoke-HarnessTestRpc 'session/list' @{_request=@{}}
    $item=$list.items | Where-Object { $_.sessionId -eq $sessionId -or $_.id -eq $sessionId } | Select-Object -First 1
    if(-not $item){continue}
    $seq=$item.projections.asOfSeq
    if($null -eq $seq){$seq=$item.projectionHints.asOfSeq}
    if($null -eq $seq){throw ('Cannot inspect Harness session cursor. Fields: '+($item.PSObject.Properties.Name -join ','))}
    $page=Invoke-HarnessTestRpc 'session/page' @{request=@{address=@{kind='session';sessionId=$sessionId};throughSeq=$seq;maxMessages=10}}
    $messages=@(Find-AssistantMessages $page)
    $ready=@($messages | Where-Object {(@($_.content | Where-Object {$_.type -eq 'text'} | ForEach-Object {$_.text}) -join '').Trim() -eq 'READY'})
    if($ready.Count -gt 0 -and -not $item.running){
        if($item.projections.values.modelSelection.lastUsed.model -ne $ExpectedModel){throw 'Harness response did not establish the expected model identity.'}
        Write-Output ('Harness prompt PASS: selected model replied READY; session '+$sessionId)
        return
    }
}while((Get-Date) -lt $deadline)
throw 'Harness accepted the prompt but did not produce a verified assistant response within 120 seconds.'
