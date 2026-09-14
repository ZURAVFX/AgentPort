$script:OmniRouteVersion='3.8.50'
$script:OmniRoutePort=20128
$script:OmniRouteProcess=$null
$script:OmniRouteOwnership=$null

function Get-AgentPortOmniRoutePaths {
    $root=Join-Path $script:AppDataDir 'omniroute'
    $package=Join-Path $root ('package-v'+$script:OmniRouteVersion)
    [pscustomobject]@{Root=$root;Package=$package;Data=(Join-Path $root 'data');Entry=(Join-Path $package 'node_modules\omniroute\bin\omniroute.mjs');Logs=(Join-Path $root 'logs')}
}

function Test-AgentPortOmniRouteInstalled {
    $paths=Get-AgentPortOmniRoutePaths
    return [IO.File]::Exists($paths.Entry)
}

function Protect-AgentPortOmniRouteKey([string]$Value){
    if([string]::IsNullOrWhiteSpace($Value)){return ''}
    return (ConvertTo-SecureString $Value -AsPlainText -Force | ConvertFrom-SecureString)
}

function Get-AgentPortOmniRouteKey {
    $encrypted=[string]$script:Config.omniroute_api_key
    if([string]::IsNullOrWhiteSpace($encrypted)){return ''}
    try{
        $secure=ConvertTo-SecureString $encrypted
        $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
    }catch{return ''}
}

function Save-AgentPortOmniRouteKey([string]$Value){
    $script:Config.omniroute_api_key=Protect-AgentPortOmniRouteKey $Value
    Save-Config
}

function Install-AgentPortOmniRoute {
    $paths=Get-AgentPortOmniRoutePaths
    $npm=Join-Path $script:PortableNodeDir 'npm.cmd'
    [void](Ensure-PortableNode)
    if(-not [IO.File]::Exists($npm)){throw 'The portable Node runtime is incomplete.'}
    if(Test-AgentPortOmniRouteInstalled){return}
    New-Item -ItemType Directory -Force -Path $paths.Root,$paths.Data,$paths.Logs | Out-Null
    $stage=$paths.Package+'.installing'
    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $out=Join-Path $paths.Logs 'install.out.log';$err=Join-Path $paths.Logs 'install.err.log'
    Set-OperationFeedback 'Installing cloud gateway' 'Downloading the tested OmniRoute package. Your provider accounts remain in OmniRoute.'
    $process=Start-Process -FilePath $npm -ArgumentList @('install','--prefix',('"'+$stage+'"'),('omniroute@'+$script:OmniRouteVersion),'--omit=dev','--no-audit','--no-fund') -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    while(-not $process.HasExited){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 150;$process.Refresh()}
    if($process.ExitCode -ne 0 -or -not [IO.File]::Exists((Join-Path $stage 'node_modules\omniroute\bin\omniroute.mjs'))){
        throw ('OmniRoute installation failed. '+(Get-RecentLogText $err 8))
    }
    if(Test-Path -LiteralPath $paths.Package){Remove-Item -LiteralPath $paths.Package -Recurse -Force}
    Move-Item -LiteralPath $stage -Destination $paths.Package
}

function Start-AgentPortOmniRoute {
    if(Test-Port $script:OmniRoutePort){
        if($script:OmniRouteOwnership -and (Test-AgentPortProcessIdentity $script:OmniRouteOwnership)){return}
        throw "Port $script:OmniRoutePort is already used by an app AgentPort does not own. Close it or change that app's port."
    }
    if(-not (Test-AgentPortOmniRouteInstalled)){Install-AgentPortOmniRoute}
    $paths=Get-AgentPortOmniRoutePaths
    New-Item -ItemType Directory -Force -Path $paths.Data,$paths.Logs | Out-Null
    $node=Join-Path $script:PortableNodeDir 'node.exe'
    $out=Join-Path $paths.Logs 'gateway.out.log';$err=Join-Path $paths.Logs 'gateway.err.log'
    $priorData=$env:DATA_DIR;$priorHost=$env:OMNIROUTE_SERVER_HOST;$priorInitialPassword=$env:INITIAL_PASSWORD
    try{
        $env:DATA_DIR=$paths.Data;$env:OMNIROUTE_SERVER_HOST='127.0.0.1';$env:INITIAL_PASSWORD=''
        $script:OmniRouteProcess=Start-Process -FilePath $node -ArgumentList @(('"'+$paths.Entry+'"'),'serve','--port',[string]$script:OmniRoutePort,'--no-open','--no-tray','--log') -WorkingDirectory $paths.Package -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        $script:OmniRouteOwnership=Get-AgentPortProcessRecord ([int]$script:OmniRouteProcess.Id) $script:OmniRouteProcess
    }finally{
        if($null -eq $priorData){Remove-Item Env:DATA_DIR -ErrorAction SilentlyContinue}else{$env:DATA_DIR=$priorData}
        if($null -eq $priorHost){Remove-Item Env:OMNIROUTE_SERVER_HOST -ErrorAction SilentlyContinue}else{$env:OMNIROUTE_SERVER_HOST=$priorHost}
        if($null -eq $priorInitialPassword){Remove-Item Env:INITIAL_PASSWORD -ErrorAction SilentlyContinue}else{$env:INITIAL_PASSWORD=$priorInitialPassword}
    }
    $deadline=(Get-Date).AddMinutes(2)
    while((Get-Date) -lt $deadline){
        $script:OmniRouteProcess.Refresh()
        if($script:OmniRouteProcess.HasExited){throw ('OmniRoute stopped during startup. '+(Get-RecentLogText $err 10))}
        try{if((Invoke-RestMethod ('http://127.0.0.1:'+ $script:OmniRoutePort +'/api/monitoring/health') -TimeoutSec 2).status -eq 'healthy'){return}}catch{}
        [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 250
    }
    throw 'OmniRoute did not become ready within two minutes.'
}

function Stop-AgentPortOmniRoute {
    if(-not $script:OmniRouteOwnership){return $false}
    $stopped=Stop-AgentPortProcess $script:OmniRouteProcess $script:OmniRouteOwnership
    if($stopped){$script:OmniRouteProcess=$null;$script:OmniRouteOwnership=$null}
    return $stopped
}

function Get-AgentPortOmniRouteModels([string]$ApiKey){
    $headers=@{}
    if(-not [string]::IsNullOrWhiteSpace($ApiKey)){$headers.Authorization='Bearer '+$ApiKey}
    $response=Invoke-RestMethod ('http://127.0.0.1:'+ $script:OmniRoutePort +'/v1/models') -Headers $headers -TimeoutSec 20
    return @($response.data | ForEach-Object {
        $explicitFree=($_.free -eq $true -or $_.isFree -eq $true -or $_.hasFree -eq $true)
        $context=if($_.context_length){[int64]$_.context_length}elseif($_.contextWindow){[int64]$_.contextWindow}else{32768}
        [pscustomobject]@{Id=[string]$_.id;Name=if($_.name){[string]$_.name}else{[string]$_.id};IsFree=[bool]$explicitFree;Context=$context}
    } | Where-Object {$_.Id -and $_.Id -notlike 'auto/*'})
}

function Open-AgentPortOmniRouteDashboard {Start-Process ('http://127.0.0.1:'+ $script:OmniRoutePort +'/dashboard/providers')}
