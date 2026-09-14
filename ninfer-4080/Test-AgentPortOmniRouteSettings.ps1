$ErrorActionPreference='Stop'

function Assert-AgentPortOmniRoute([bool]$Condition,[string]$Message){
    if(-not $Condition){throw "ASSERTION FAILED: $Message"}
}

$script:OmniRouteCapturedOperations=$null
$script:OmniRouteCapturedPath=''
try {
    . (Join-Path $PSScriptRoot 'AgentPort.Settings.ps1')
    # Keep this test offline and independent of the optional Node/YAML runtime.
    function Invoke-AgentPortYamlSettingsMutation {
        param([string]$Path,[object[]]$Operations,[string]$BackupPath)
        $script:OmniRouteCapturedPath=$Path
        $script:OmniRouteCapturedOperations=@($Operations)
        return $true
    }

    $path=Join-Path ([IO.Path]::GetTempPath()) ('omniroute-settings-'+[guid]::NewGuid().ToString('N')+'.yaml')
    [void](Set-AgentPortOmniRouteSettings -Path $path -Model 'provider/exact-model' -DisplayName 'Selected OmniRoute model' -Context 24576 -MaxTokens 2048)
    Assert-AgentPortOmniRoute ($script:OmniRouteCapturedPath -ceq $path) 'settings path was not forwarded'
    Assert-AgentPortOmniRoute (@($script:OmniRouteCapturedOperations).Count -eq 2) 'provider and default operations were not emitted'
    $ensure=$script:OmniRouteCapturedOperations[0]
    $provider=$ensure.value
    Assert-AgentPortOmniRoute ($ensure.kind -ceq 'ensure-provider' -and $ensure.provider -ceq 'agentport-omniroute') 'wrong provider operation'
    Assert-AgentPortOmniRoute ($provider.displayName -ceq 'OmniRoute Cloud') 'wrong provider display name'
    Assert-AgentPortOmniRoute ($provider.apiKeyEnv -ceq 'OMNIROUTE_API_KEY') 'wrong runtime key environment name'
    Assert-AgentPortOmniRoute ($provider.api -ceq 'openai-completions') 'wrong provider API'
    Assert-AgentPortOmniRoute ($provider.baseURL -ceq 'http://127.0.0.1:20128/v1') 'provider is not loopback-only'
    Assert-AgentPortOmniRoute (@($provider.defaultInput).Count -eq 1 -and $provider.defaultInput[0] -ceq 'text') 'provider was not text-only'
    Assert-AgentPortOmniRoute ($provider.models[0].id -ceq 'provider/exact-model') 'selected model id was changed'
    Assert-AgentPortOmniRoute ($provider.models[0].name -ceq 'Selected OmniRoute model') 'selected model label was changed'
    Assert-AgentPortOmniRoute ([int]$provider.models[0].contextWindow -eq 24576 -and [int]$provider.models[0].maxTokens -eq 2048) 'context limits were not preserved'
    Assert-AgentPortOmniRoute ($script:OmniRouteCapturedOperations[1].kind -ceq 'set-default-model' -and $script:OmniRouteCapturedOperations[1].model -ceq 'provider/exact-model') 'default model did not remain exact'
    $serialized=ConvertTo-Json $script:OmniRouteCapturedOperations -Depth 12 -Compress
    Assert-AgentPortOmniRoute ($serialized -notmatch 'secret-token-value') 'a plaintext credential leaked into settings operations'

    [void](Set-AgentPortOmniRouteSettings -Path $path -Model 'provider/explicit-only' -SetDefault $false)
    Assert-AgentPortOmniRoute (@($script:OmniRouteCapturedOperations).Count -eq 1) 'optional default operation was emitted when disabled'
    Assert-AgentPortOmniRoute ($script:OmniRouteCapturedOperations[0].value.models[0].id -ceq 'provider/explicit-only') 'explicit model was not preserved on update'
    Write-Host 'AgentPort OmniRoute settings tests passed.' -ForegroundColor Green
} finally {
    if($path -and (Test-Path -LiteralPath $path)){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
}
