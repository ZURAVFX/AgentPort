param([string]$HarnessRoot,[string]$ComfyUrl='http://127.0.0.1:8188',[int]$Context=49152,[string]$ExistingModel='',[string]$ModelPath='',[switch]$Team,[switch]$Blender,[int]$MaxTokens=4096,[string]$Prompt='Use the connected comfy-mcp system_stats tool to report the running ComfyUI GPU name. Use MCP directly. Do not modify anything. After the tool returns, reply with the GPU name and stop.')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'NInfer.Runtime.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.NInfer.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Mcp.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Presets.ps1')
. (Join-Path $PSScriptRoot 'AgentPort.Team.ps1')
$resultRoot=Join-Path $PSScriptRoot 'results\agentic-mcp'
New-Item -ItemType Directory -Force -Path $resultRoot | Out-Null
$script:ConfigDir=$resultRoot
$script:SettingsPath=Join-Path $resultRoot 'settings.yaml'
function Ensure-ConfigDir {}
Update-NInferHarnessSettings $Context $MaxTokens
if($ExistingModel){$text=[IO.File]::ReadAllText($script:SettingsPath).Replace('qwen3.8-27b-minq4',$ExistingModel);[IO.File]::WriteAllText($script:SettingsPath,$text)}
if($Team){$script:Config=@{harness_root=$HarnessRoot;harness_skills_root=(Join-Path $env:USERPROFILE '.dsh\harness_skills')};Install-AgentPortTeamPreset}
$command=Resolve-AgentPortMcpCommand 'comfy-mcp'
$config=[pscustomobject]@{serverName='comfy-mcp';transport='stdio';command=$command;args=@();env=@{COMFY_BIN=(Join-Path (Split-Path $command) 'comfy.exe');COMFY_LOCAL_URL=$ComfyUrl;PYTHONUTF8='1';PYTHONIOENCODING='utf-8'};toolCallTimeoutMs=180000;failOnStartupError=$true}
$settings=@{useWithNInfer=$true;servers=@(@{name='comfy-mcp';enabled=$true;config=$config})}
if($Blender){$settings.servers+=@{name='blender-mcp';enabled=$true;config=@{serverName='blender-mcp';transport='stdio';command=(Resolve-AgentPortMcpCommand 'blender-mcp');args=@();toolCallTimeoutMs=180000;failOnStartupError=$true}}}
[IO.File]::WriteAllText((Join-Path $resultRoot 'agentport-mcp.json'),($settings | ConvertTo-Json -Depth 10))
$probe=Test-AgentPortMcpConnection $config 'server_info'
Write-Host "ComfyUI live check passed: $($probe.count) tools."
$mcpPatch=Write-AgentPortMcpOverlay (Join-Path $resultRoot 'mcp.json') -NInfer
$patch=New-NInferHarnessPatch (Join-Path $resultRoot 'patch.yml') $script:SettingsPath
$state=$null
$teamProcess=$null
try{
    if($ModelPath){
        if(-not $ExistingModel){throw 'ModelPath requires ExistingModel as the local API model id.'}
        try{$ready=Invoke-RestMethod http://127.0.0.1:5100/health -TimeoutSec 1}catch{$ready=$null}
        if($ready.status -ne 'ok'){
            $runtime=Get-AgentPortTeamRuntime
            if(-not $runtime -or -not(Test-Path $ModelPath)){throw 'Requested test model runtime or file is missing.'}
            $teamProcess=Start-Process $runtime -ArgumentList @('-m',('"'+$ModelPath+'"'),'--host','127.0.0.1','--port','5100','--api-key','local-textgen','--alias',$ExistingModel,'-c',$Context,'-ngl','99','--fit-target','768','-ctk','q4_0','-ctv','q4_0','--parallel','1','--reasoning','off','--no-reasoning-preserve','--metrics') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $resultRoot 'test-model.out.log') -RedirectStandardError (Join-Path $resultRoot 'test-model.err.log')
            $deadline=(Get-Date).AddMinutes(5)
            do { Start-Sleep -Milliseconds 200; try{$ready=Invoke-RestMethod http://127.0.0.1:5100/health -TimeoutSec 1}catch{$ready=$null} } while($ready.status -ne 'ok' -and (Get-Date) -lt $deadline)
            if($ready.status -ne 'ok'){throw 'Test model did not become ready.'}
        }
    } elseif($ExistingModel -eq 'agentport-team-qwen9b'){
        # The production launcher owns this process in normal use. The test runner
        # starts an isolated copy only when the local service is not already ready.
        try{$ready=Invoke-RestMethod http://127.0.0.1:5100/health -TimeoutSec 1}catch{$ready=$null}
        if($ready.status -ne 'ok'){
            $runtime=Get-AgentPortTeamRuntime
            $model=Join-Path $env:LOCALAPPDATA 'AgentPort\models\Qwen3.8-9B-Q4_K_M.gguf'
            if(-not $runtime -or -not(Test-Path $model)){throw 'Team model runtime is not installed.'}
            $teamProcess=Start-Process $runtime -ArgumentList @('-m',('"'+$model+'"'),'--host','127.0.0.1','--port','5100','--api-key','local-textgen','--alias',$ExistingModel,'-c',$Context,'-ngl','99','--fit-target','1536','-ctk','q4_0','-ctv','q4_0','--parallel','1','--reasoning','off','--metrics') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $resultRoot 'test-team.out.log') -RedirectStandardError (Join-Path $resultRoot 'test-team.err.log')
            $deadline=(Get-Date).AddMinutes(5)
            do { Start-Sleep -Milliseconds 200; try{$ready=Invoke-RestMethod http://127.0.0.1:5100/health -TimeoutSec 1}catch{$ready=$null} } while($ready.status -ne 'ok' -and (Get-Date) -lt $deadline)
            if($ready.status -ne 'ok'){throw 'Team model did not become ready.'}
        }
    } elseif(-not $ExistingModel){$state=Start-NInferService -Context $Context -LogDirectory $resultRoot}
    $env:NINFER_API_KEY='local-textgen'
    Push-Location $resultRoot
    try{
        $loader=([Uri](Join-Path $HarnessRoot 'node_modules/tsx/dist/esm/index.mjs')).AbsoluteUri
        $env:TSX_TSCONFIG_PATH=Join-Path $HarnessRoot 'tsconfig.json'
        & node --import $loader (Join-Path $HarnessRoot 'apps/cli/src/bin.ts') --profile headless --patch $patch --patch $mcpPatch $Prompt
        if($LASTEXITCODE){throw "Harness exited $LASTEXITCODE"}
    }finally{Pop-Location}
}finally{if($state){Stop-NInferService $state};if($teamProcess -and -not $teamProcess.HasExited){& taskkill.exe /PID $teamProcess.Id /T /F | Out-Null}}
