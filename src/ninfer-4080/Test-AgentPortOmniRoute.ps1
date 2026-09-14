$ErrorActionPreference='Stop'
$script:AppDataDir=Join-Path ([IO.Path]::GetTempPath()) ('agentport-omniroute-'+[guid]::NewGuid().ToString('N'))
$script:Config=[ordered]@{omniroute_api_key=''}
function Save-Config {}
. (Join-Path $PSScriptRoot 'AgentPort.OmniRoute.ps1')

function Assert-AgentPortOmniRoute([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Invoke-RestMethod {
    param([Parameter(Position=0)]$Uri,$Headers,$TimeoutSec)
    [pscustomobject]@{data=@(
        [pscustomobject]@{id='auto/best-coding';context_length=1000000},
        [pscustomobject]@{id='provider/exact-free';name='Exact free';context_length=131072;isFree=$true},
        [pscustomobject]@{id='provider/exact-paid';contextWindow=65536}
    )}
}

try {
    Assert-AgentPortOmniRoute ($script:OmniRouteVersion -eq '3.8.50') 'The pinned package must be an npm-published version.'
    $cipher=Protect-AgentPortOmniRouteKey 'secret-token-value'
    Assert-AgentPortOmniRoute ($cipher -and $cipher -notmatch 'secret-token-value') 'The endpoint key was not protected.'
    $script:Config.omniroute_api_key=$cipher
    Assert-AgentPortOmniRoute ((Get-AgentPortOmniRouteKey) -eq 'secret-token-value') 'The protected endpoint key could not be read.'
    $models=@(Get-AgentPortOmniRouteModels 'key')
    Assert-AgentPortOmniRoute ($models.Count -eq 2) 'Automatic routes must not be offered as exact provider routes.'
    Assert-AgentPortOmniRoute ($models[0].Context -eq 131072 -and $models[0].IsFree) 'Current model metadata was parsed incorrectly.'
    Assert-AgentPortOmniRoute ($models[1].Context -eq 65536 -and -not $models[1].IsFree) 'Legacy model metadata was parsed incorrectly.'
    Write-Host 'AgentPort OmniRoute gateway tests passed.'
} finally {
    Remove-Item -LiteralPath $script:AppDataDir -Recurse -Force -ErrorAction SilentlyContinue
}
