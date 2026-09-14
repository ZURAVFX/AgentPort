$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'AgentPort.AutoContinue.ps1')
$script:FixturePath=Join-Path ([IO.Path]::GetTempPath()) ('agentport-auto-continue-'+[guid]::NewGuid().ToString('N')+'.json')
function Get-AgentPortAutoContinuePath { $script:FixturePath }
try {
    if((Get-AgentPortAutoContinueOptions).enabled){throw 'Missing options must default off'}
    Save-AgentPortAutoContinueOptions $true 20
    $read=Get-AgentPortAutoContinueOptions
    if(-not $read.enabled -or $read.maxContinuations -ne 20){throw 'Options did not persist'}
    Save-AgentPortAutoContinueOptions $false 10
    if((Get-AgentPortAutoContinueOptions).enabled){throw 'Disable did not persist'}
    $failed=$false
    try {Save-AgentPortAutoContinueOptions $true 51}catch{$failed=$true}
    if(-not $failed){throw 'Excessive limit accepted'}
    [IO.File]::WriteAllText($script:FixturePath,'invalid')
    if((Get-AgentPortAutoContinueOptions).enabled){throw 'Invalid options must fail closed'}
    Write-Host 'Auto-continue settings persistence tests passed.'
} finally {foreach($file in @($script:FixturePath,($script:FixturePath+'.previous'))){if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -Force}}}
