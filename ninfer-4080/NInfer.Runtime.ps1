# Shared lifecycle for the benchmark and AgentPort. Windows PowerShell 5.1 compatible.
function Invoke-NInferShell {
    param([string]$Distro,[string]$Text,[string]$Directory)
    $path=Join-Path $Directory ('command-'+[guid]::NewGuid().ToString('N')+'.sh')
    [IO.File]::WriteAllText($path,$Text.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    try {
        $linuxPath=((& wsl.exe -d $Distro --exec wslpath -u $path.Replace('\','/')) -join '').Trim()
        if($LASTEXITCODE -ne 0){throw 'Cannot translate script path into WSL.'}
        $result=& wsl.exe -d $Distro --exec bash $linuxPath
        if($LASTEXITCODE -ne 0){throw "NInfer control command failed: $($result -join ' ')"}
        return $result
    } finally {Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}
}

function Start-NInferService {
    param([string]$Distro='Ubuntu-24.04',[int]$Context=24576,
          [int]$Draft=3,[int]$Port=5100,[string]$LogDirectory=(Join-Path $env:LOCALAPPDATA 'AgentPort\ninfer'),
          [int]$TimeoutSeconds=120,[ValidateSet(64,128,256)][int]$Prefill=64)
    if($Context -lt 2048 -or $Context -gt 131072){throw 'NInfer context must be between 2048 and 131072.'}
    if($Draft -lt 0 -or $Draft -gt 6){throw 'Draft must be between 0 (off) and 6.'}
    if($Port -lt 1024 -or $Port -gt 65535){throw 'Invalid port.'}
    $gpuFree=((& wsl.exe -d $Distro --exec /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) | Select-Object -First 1)
    if($LASTEXITCODE -ne 0){throw 'Cannot query NVIDIA GPU memory in WSL.'}
    if([int]$gpuFree -lt 14600){throw "NInfer needs approximately 14,600 MiB of free GPU memory; $gpuFree MiB is free. Close other loaded models or GPU applications and retry."}
    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
    $LogDirectory=(Resolve-Path -LiteralPath $LogDirectory).Path
    $socket=[Net.Sockets.TcpClient]::new()
    try {
        if($socket.ConnectAsync('127.0.0.1',$Port).Wait(500) -and $socket.Connected){throw "Port $Port is already occupied. Stop its backend explicitly first; no unrelated process will be killed."}
    } catch [AggregateException] {} finally {$socket.Dispose()}
    $linuxHome=((& wsl.exe -d $Distro -- printenv HOME) -join '').Trim()
    if($LASTEXITCODE -ne 0 -or $linuxHome -notmatch '^/[A-Za-z0-9._/-]+$'){throw "Cannot resolve absolute Linux HOME in $Distro."}
    $root="$linuxHome/.agentport"
    $exe="$root/ninfer-src/build-sm89/apps/ninfer-serve"
    $artifact="$root/models/qwen3_8_27b_minq4.ninfer"
    Invoke-NInferShell $Distro "set -e`ntest -x '$exe'`ntest -s '$artifact'" $LogDirectory | Out-Null
    $tag=[guid]::NewGuid().ToString('N')
    $launch=Join-Path $LogDirectory "launch-$tag.sh"
    $pidFile="$root/logs/agentport-$tag.pid"
    $model='qwen3.8-27b-minq4'
    $spec=if($Draft -eq 0){''}else{"--spec mtp --draft-tokens $Draft --lm-head-draft"}
    $command=@"
set -euo pipefail
mkdir -p '$root/logs'
echo `$$ > '$pidFile'
exec '$exe' '$artifact' --host 127.0.0.1 --port $Port --api-key local-textgen --model-id '$model' --max-context $Context --kv-capacity $Context --max-concurrency 1 --prefill-chunk $Prefill --kv-dtype i4 $spec --preserve-thinking
"@
    [IO.File]::WriteAllText($launch,$command.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
    $linuxLaunch=((& wsl.exe -d $Distro --exec wslpath -u $launch.Replace('\','/')) -join '').Trim()
    $out=Join-Path $LogDirectory "$tag.out.log"
    $err=Join-Path $LogDirectory "$tag.err.log"
    $process=Start-Process wsl.exe -ArgumentList @('-d', $Distro,'--','bash',('"'+$linuxLaunch+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $state=[pscustomobject]@{Process=$process;Distro=$Distro;Executable=$exe;PidFile=$pidFile;LogDirectory=$LogDirectory;Out=$out;Err=$err;Launch=$launch;Model=$model;Context=$Context;Draft=$Draft;Port=$Port;BaseUrl="http://127.0.0.1:$Port/v1"}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $nextReport=0
    try {
        while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            $process.Refresh()
            $tail=((Get-Content -LiteralPath $out,$err -Tail 12 -ErrorAction SilentlyContinue) -join "`n")
            $firstError=Get-Content -LiteralPath $out,$err -ErrorAction SilentlyContinue | Select-String '\[error\]|^error:' | Select-Object -First 1
            if($firstError){$tail=[string]$firstError+"`n"+$tail}
            if($process.HasExited){throw "NInfer exited ($($process.ExitCode)) after $([int]$clock.Elapsed.TotalSeconds)s.`n$tail"}
            if($tail -match '(?im)^error:|CUDA error|out of memory'){throw "NInfer startup failed.`n$tail"}
            try {
                $models=Invoke-RestMethod ($state.BaseUrl+'/models') -Headers @{Authorization='Bearer local-textgen'} -TimeoutSec 2
                if($models.data){
                    $matched=@($models.data | Where-Object {$_.id -eq $model -and $_.owned_by -eq 'ninfer'})
                    if($matched.Count -eq 0){throw 'IDENTITY: Port answered with a different backend/model.'}
                    Write-Host "NInfer ready: $model, context $Context, draft $Draft ($([int]$clock.Elapsed.TotalSeconds)s)."
                    return $state
                }
            } catch {if($_.Exception.Message -like 'IDENTITY:*'){throw}}
            if($clock.Elapsed.TotalSeconds -ge $nextReport){
                Write-Host "Loading NInfer ($([int]$clock.Elapsed.TotalSeconds)s)... $((($tail -split "`n") | Select-Object -Last 1))"
                $nextReport=$clock.Elapsed.TotalSeconds+5
            }
            Start-Sleep -Milliseconds 300
        }
        throw "NInfer startup timed out. Logs: $out and $err`n$tail"
    } catch {
        Stop-NInferService $state
        throw
    }
}

function Stop-NInferService {
    param($State)
    if(-not $State){return}
    # Only signal the exact Linux PID created by this instance, after checking its executable.
    $command=@'
set -eu
if test -f '__PID__'; then
  read -r target < '__PID__'
  case "$target" in ''|*[!0-9]*) exit 2;; esac
  if test "$(readlink /proc/$target/exe 2>/dev/null || true)" = '__EXE__'; then
    kill -TERM "$target"
    for n in {1..40}; do test ! -e /proc/$target && break; sleep 0.1; done
    if test "$(readlink /proc/$target/exe 2>/dev/null || true)" = '__EXE__'; then kill -KILL "$target"; fi
  fi
  rm -f '__PID__'
fi
'@
    try {Invoke-NInferShell $State.Distro ($command.Replace('__PID__',$State.PidFile).Replace('__EXE__',$State.Executable)) $State.LogDirectory | Out-Null}
    finally {Remove-Item -LiteralPath $State.Launch -ErrorAction SilentlyContinue}
    if($State.Process){[void]$State.Process.WaitForExit(10000)}
    # WSL's Windows forwarding socket can outlive the Linux process briefly.
    for($attempt=0;$attempt -lt 30;$attempt++){
        $probe=[Net.Sockets.TcpClient]::new()
        try {
            if(-not $probe.ConnectAsync('127.0.0.1',$State.Port).Wait(200) -or -not $probe.Connected){break}
        } catch {break} finally {$probe.Dispose()}
        Start-Sleep -Milliseconds 200
    }
}
