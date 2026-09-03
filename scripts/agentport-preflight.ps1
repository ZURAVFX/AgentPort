<#
AgentPort preflight helper
Checks install state and scans common local AI model folders.
#>

$ErrorActionPreference = 'SilentlyContinue'

function Test-PathAny($Paths) {
    foreach ($p in $Paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $true }
    }
    return $false
}

function Get-TextGenStatus([string]$Root) {
    $checks = [ordered]@{
        start_windows = Test-Path -LiteralPath (Join-Path $Root 'start_windows.bat')
        server_py = Test-Path -LiteralPath (Join-Path $Root 'server.py')
        python_env = Test-Path -LiteralPath (Join-Path $Root 'installer_files\env\python.exe')
        models_dir = Test-Path -LiteralPath (Join-Path $Root 'user_data\models')
    }
    $hits = @($checks.Values | Where-Object { $_ }).Count
    $state = if ($checks.start_windows -and ($checks.server_py -or $checks.python_env)) { 'Installed' } elseif ($hits -gt 0) { 'Needs repair' } else { 'Missing' }
    [pscustomobject]@{ component='TextGen'; root=$Root; state=$state; checks=$checks }
}

function Get-HarnessStatus([string]$Root) {
    $checks = [ordered]@{
        package_json = Test-Path -LiteralPath (Join-Path $Root 'package.json')
        node_modules = Test-Path -LiteralPath (Join-Path $Root 'node_modules')
        pnpm_lock = Test-Path -LiteralPath (Join-Path $Root 'pnpm-lock.yaml')
    }
    $state = if ($checks.package_json -and ($checks.node_modules -or $checks.pnpm_lock)) { 'Installed' } elseif ($checks.package_json) { 'Needs repair' } else { 'Missing' }
    [pscustomobject]@{ component='DeepSeek Harness'; root=$Root; state=$state; checks=$checks }
}

function Get-ModelSearchRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    function AddRoot($Source, $Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        if (Test-Path -LiteralPath $Path) {
            $roots.Add([pscustomobject]@{ source=$Source; path=$Path }) | Out-Null
        }
    }

    AddRoot 'AgentPort/TextGen' 'C:\AI\textgen\user_data\models'
    AddRoot 'Ollama env' $env:OLLAMA_MODELS
    AddRoot 'Ollama default' (Join-Path $env:USERPROFILE '.ollama\models')
    AddRoot 'LM Studio default' (Join-Path $env:USERPROFILE '.lmstudio\models')
    AddRoot 'LM Studio appdata' (Join-Path $env:APPDATA 'LM Studio\models')
    AddRoot 'Unsloth env' $env:UNSLOTH_STUDIO_HOME
    AddRoot 'Unsloth studio' (Join-Path $env:USERPROFILE '.unsloth\studio')
    AddRoot 'Hugging Face env' $env:HUGGINGFACE_HUB_CACHE
    AddRoot 'Hugging Face home' $(if ($env:HF_HOME) { Join-Path $env:HF_HOME 'hub' } else { $null })
    AddRoot 'Hugging Face default' (Join-Path $env:USERPROFILE '.cache\huggingface\hub')
    AddRoot 'Jan default' (Join-Path $env:USERPROFILE 'jan\models')
    AddRoot 'Jan appdata' (Join-Path $env:APPDATA 'Jan\models')
    AddRoot 'GPT4All localappdata' (Join-Path $env:LOCALAPPDATA 'nomic.ai\GPT4All')
    AddRoot 'GPT4All appdata' (Join-Path $env:APPDATA 'nomic.ai\GPT4All')
    return $roots
}

function Get-QuantFromName([string]$Name) {
    if ($Name -match '(Q[2-8]_[A-Z]_[A-Z]|Q[2-8]_K|Q[2-8]_K_[A-Z]|IQ[0-9]_[A-Z]+|F16|BF16)') { return $Matches[1] }
    return 'Unknown'
}

function Find-GgufModels {
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-ModelSearchRoots) {
        Get-ChildItem -LiteralPath $root.path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -ieq '.gguf' -or $_.Name -match '^sha256-|^models--|blob'
        } | ForEach-Object {
            $isMmproj = $_.Name -match 'mmproj'
            $helpers = @(Get-ChildItem -LiteralPath $_.DirectoryName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'mmproj.*\.gguf|.*mmproj.*\.gguf' })
            $helperState = if ($isMmproj) { 'Helper file' } elseif ($helpers.Count -gt 0) { 'Helper detected' } else { 'No helper detected' }
            $results.Add([pscustomobject]@{
                source = $root.source
                name = $_.Name
                path = $_.FullName
                size_gb = [math]::Round($_.Length / 1GB, 2)
                quant = Get-QuantFromName $_.Name
                helper = $helperState
            }) | Out-Null
        }
    }
    return $results | Sort-Object source, name
}

$configDir = Join-Path $env:USERPROFILE '.dsh'
$configFile = Join-Path $configDir 'launcher_config.json'
$config = $null
if (Test-Path -LiteralPath $configFile) {
    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
}

$textgenRoot = if ($config -and $config.textgen_root) { [string]$config.textgen_root } else { 'C:\AI\textgen' }
$harnessRoot = if ($config -and $config.harness_root) { [string]$config.harness_root } else { Join-Path $env:USERPROFILE 'Desktop\deepseek-harness' }

[pscustomobject]@{
    generated_at = (Get-Date).ToString('s')
    textgen = Get-TextGenStatus $textgenRoot
    deepseek_harness = Get-HarnessStatus $harnessRoot
    model_roots = Get-ModelSearchRoots
    models = @(Find-GgufModels)
} | ConvertTo-Json -Depth 8
