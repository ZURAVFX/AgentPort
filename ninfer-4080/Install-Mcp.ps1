param([ValidateSet('comfy','blender','checker')][string]$Tool='checker')
$ErrorActionPreference='Stop'
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONUTF8='1'
$root=Join-Path $env:LOCALAPPDATA 'AgentPort\mcp'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$uv=Get-Command uv.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if($uv){$uv=$uv.Source}else{
    $uv=Join-Path $root 'uv\uv.exe'
    if(-not(Test-Path $uv)){
        Write-Host 'Downloading the Python installer...'
        $archive=Join-Path $root 'uv.zip'
        Invoke-WebRequest 'https://github.com/astral-sh/uv/releases/download/0.8.22/uv-x86_64-pc-windows-msvc.zip' -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $root 'uv') -Force
    }
}
$venv=Join-Path $root $Tool
$python=Join-Path $venv 'Scripts\python.exe'
if(-not(Test-Path $python)){
    & $uv venv --python 3.12 $venv
    if($LASTEXITCODE){throw 'Python installation failed. Check your internet connection and retry.'}
}
$packages=@(switch($Tool){
    'comfy' {@('comfy-mcp==0.10.0','comfy-cli==1.20.0')}
    # The similarly named PyPI package is a different, unofficial Blender server.
    'blender' {@('git+https://projects.blender.org/lab/blender_mcp.git@03004fd0216bfe5e0a3d9ac9b47d5efadc3d78c4#subdirectory=mcp','mcp==1.29.1')}
    'checker' {@('mcp==1.29.1')}
})
if($Tool -eq 'blender' -and -not(Get-Command git.exe -ErrorAction SilentlyContinue)){
    Write-Host 'Installing portable Git for the official Blender download...'
    $gitRoot=Join-Path $root 'git'
    $release=Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest'
    $asset=@($release.assets | Where-Object name -match '^MinGit-.*-64-bit.zip$' | Select-Object -First 1)
    if(-not $asset){throw 'Portable Git download was not found. Install Git for Windows and retry.'}
    $zip=Join-Path $root 'git.zip'
    Invoke-WebRequest $asset[0].browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $gitRoot -Force
    $env:PATH=(Join-Path $gitRoot 'cmd')+';'+$env:PATH
}
Write-Host "Installing $Tool connection..."
& $uv pip install --python $python @packages
if($LASTEXITCODE){throw 'MCP installation failed. See the download error above and retry.'}
Write-Host 'Installation complete.'
