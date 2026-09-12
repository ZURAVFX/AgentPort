param([switch]$RuntimeOnly)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'AgentPort'
$runtime=Join-Path $root 'llama-b10809'
$models=Join-Path $root 'models'
New-Item -ItemType Directory -Force -Path $runtime,$models | Out-Null
function Get-VerifiedDownload([string]$Url,[string]$Path,[string]$Hash){
    if((Test-Path $Path) -and (Get-FileHash $Path -Algorithm SHA256).Hash -eq $Hash){return}
    $part=$Path+'.part'
    Write-Host ('Downloading '+[IO.Path]::GetFileName($Path)+'...')
    & curl.exe --location --fail --retry 2 --continue-at - --output $part $Url
    if($LASTEXITCODE){throw 'Download interrupted. Click Download and start again to resume.'}
    if((Get-FileHash $part -Algorithm SHA256).Hash -ne $Hash){
        Move-Item -LiteralPath $part -Destination ($part+'.invalid-'+[guid]::NewGuid().ToString('N'))
        throw 'The download checksum did not match. The invalid file was retained for inspection; retry to download again.'
    }
    Move-Item -LiteralPath $part -Destination $Path -Force
}
$assets=@(
    @('llama-b10809-bin-win-cuda-12.4-x64.zip','c77bfcd9ed8d91e8721a2d6a290b907fddd4fa5412a47b21c6fa1709116b85f9'),
    @('cudart-llama-bin-win-cuda-12.4-x64.zip','8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6')
)
foreach($asset in $assets){
    $archive=Join-Path $root $asset[0]
    Get-VerifiedDownload ('https://github.com/ggml-org/llama.cpp/releases/download/b10809/'+$asset[0]) $archive $asset[1]
    Expand-Archive -LiteralPath $archive -DestinationPath $runtime -Force
}
if(-not $RuntimeOnly){
    Get-VerifiedDownload 'https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-UD-IQ3_XXS.gguf' (Join-Path $models 'Qwen3-Coder-30B-A3B-Instruct-UD-IQ3_XXS.gguf') 'D6B85D2B6633C55BE3751848ACC74FAB40D28D93B27DABACD96CEABE10962057'
    Write-Host 'Recommended model and CUDA runtime verified.'
}else{Write-Host 'Managed CUDA runtime verified.'}
