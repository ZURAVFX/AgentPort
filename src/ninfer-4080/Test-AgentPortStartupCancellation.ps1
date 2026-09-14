param([string]$RuntimePath=(Join-Path $PSScriptRoot '..\AgentPort-runtime-v1.7.0-4080.ps1'))
$ErrorActionPreference='Stop'

# Exercise the production control flow without starting/stopping processes,
# touching runtime files, opening WPF windows, or requiring a GPU.
$tokens=$null;$parseErrors=$null
$runtimeFullPath=(Resolve-Path -LiteralPath $RuntimePath).Path
$ast=[Management.Automation.Language.Parser]::ParseFile($runtimeFullPath,[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors.Message -join '; ')}
$required=@('Start-UnifiedStack','Poll-Launch','Start-Harness','Start-AgentPortStopOperation','Set-StopControls','Update-AgentPortLifecycleControls','Test-ModelMatch')
$runtimeRoot=(Split-Path $runtimeFullPath).Replace("'","''")
foreach($name in $required){
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(-not $definition){throw "Production function missing: $name"}
    Invoke-Expression ($definition.Extent.Text.Replace('$PSScriptRoot',("'"+$runtimeRoot+"'")))
}

function Assert-Startup($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Invoke-ReentrantStop([string]$Point){
    if($script:Injected -or $Point -ne $script:InjectAt){return}
    $script:Injected=$true
    Assert-Startup (Start-AgentPortStopOperation $script:StopKind) 'Fixture stop was not accepted.'
    if($script:CompleteStopDuringPump){
        # A fast background worker can finish before the outer launch resumes.
        # Retain its generation change so an Active-only check cannot pass.
        $script:StopOperation.Active=$false
        $script:StopOperation.Kind=''
        $script:StopOperation.Generation++
        $script:RuntimeSnapshot=$null
    }
}
function Set-FixtureRuntimeSnapshot([bool]$HarnessOnline=$false){
    $script:RuntimeSnapshot=[pscustomobject]@{
        BackendOnline=$true;HarnessOnline=$HarnessOnline;LoadedModel='model.gguf'
        StopGeneration=[int]$script:StopOperation.Generation
    }
}
function Reset-StartupFixture([string]$Point='',[string]$Kind='harness',[bool]$Complete=$true){
    $script:InjectAt=$Point;$script:StopKind=$Kind;$script:CompleteStopDuringPump=$Complete;$script:Injected=$false
    $script:LaunchState='idle';$script:LaunchPhase=0;$script:TeamStarting=$false
    $script:ModelStopGeneration=0;$script:SuppressHarnessStart=$false;$script:HarnessOnlyLaunch=$false
    $script:StopOperation=[pscustomobject]@{Active=$false;Generation=0;Kind='';StartedAt=$null;Handle=$null}
    $script:Config=@{active_model='old.gguf';active_context_tokens=49152;harness_root='C:\fixture\harness';harness_runtime='npx-latest';textgen_root='C:\fixture\textgen'}
    $script:ContextPresets=@{'48k'=49152};$script:OffloadModes=@{auto=@{gpu_layers=99;fit_target=768}}
    $script:BackendPort=15100;$script:AppDataDir='C:\fixture';$script:NpmCacheDir='C:\fixture\npm';$script:PortableNodeDir='C:\fixture\node'
    $script:TextGenProcess=$null;$script:TextGenOwnership=$null;$script:HarnessProcess=$null;$script:HarnessOwnership=$null;$script:NInferState=$null
    $script:PendingModel='model.gguf';$script:PendingContext=49152;$script:TeamHarnessPatch=$null;$script:NInferHarnessPatch=$null
    Set-FixtureRuntimeSnapshot
    $script:ProcessStarts=New-Object System.Collections.Generic.List[string]
    $script:BackgroundStarts=0;$script:LastFeedback='';$script:OpenHarnessWhenReady=$false
    $script:ContextCombo=[pscustomobject]@{SelectedItem='48k'}
    $script:CacheCombo=[pscustomobject]@{SelectedItem='q4_0'}
    $script:OffloadCombo=[pscustomobject]@{SelectedItem='auto'}
    $script:SpecCombo=[pscustomobject]@{SelectedItem='Off'}
    $script:MaxTokensCombo=[pscustomobject]@{SelectedItem='2048'}
    foreach($name in @('PrimaryButton','StopBackendButton','StopHarnessButton','PurgeVramButton','RuntimeOpenUiButton','ModelControlStatus','HarnessControlStatus','LaunchProgressCard','LaunchProgress','LaunchDetailText')){
        Set-Variable -Name $name -Scope Script -Value ([pscustomobject]@{IsEnabled=$true;Content='';Text='';Visibility='Collapsed';Value=0})
    }
}

# External boundaries are stubbed. The startup, stop routing, generation
# handling and backend-ready poll above are extracted from the actual source.
function Get-SelectedModel {[pscustomobject]@{Source='GGUF';FullPath='C:\fixture\model.gguf';RelPath='model.gguf';Name='Fixture model';HelperFiles=@()}}
function Test-Port {return $false}
function Test-Path {return $true}
function New-Item {}
function Start-Sleep {}
function Save-Config {}
function Ensure-AgentPortRuntimeDirs {}
function Update-HarnessSettings {}
function Repair-HarnessSettingsFile {}
function Repair-AgentPortPresetCompatibility {}
function Ensure-AgentPortSkillIsolation {}
function Prepare-IsolatedHarnessSkills {Invoke-ReentrantStop 'harness-preparation'}
function Ensure-PortableNode {return 'C:\fixture\node\npx.cmd'}
function Write-AgentPortMcpOverlay {}
function Get-AgentPortTeamRuntime {return 'C:\fixture\llama-server.exe'}
function Kill-Stack {Invoke-ReentrantStop 'kill-stack'}
function Set-LaunchPhase {
    param($Step,$Title,$Detail,$Percent,$State)
    $script:LaunchPhase=$Step
    if($Step -eq 4 -and $Percent -eq 42){Invoke-ReentrantStop 'before-model-spawn'}
}
function Set-Log {}
function Set-OperationFeedback {param($Title,$Detail,$State);$script:LastFeedback=$Title}
function Refresh-Runtime {}
function Update-BackendSelectionUi {}
function Get-RecentLogText {return ''}
function New-AgentPortBackgroundOperation {
    param($Name,$ScriptText,$Payload,$TimeoutSeconds)
    $script:BackgroundStarts++
    return [pscustomobject]@{Name=$Name}
}
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError,$WorkingDirectory)
    [void]$script:ProcessStarts.Add([string]$FilePath)
    $process=[pscustomobject]@{Id=(1000+$script:ProcessStarts.Count);HasExited=$false;ExitCode=0}
    $process | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
    return $process
}
function Get-AgentPortProcessRecord {param($ProcessId,$Process);return [pscustomobject]@{Pid=$ProcessId}}

$cases=0
foreach($point in @('kill-stack','before-model-spawn')){
    foreach($kind in @('backend','all')){
        foreach($complete in @($false,$true)){
            Reset-StartupFixture $point $kind $complete
            Start-UnifiedStack
            Assert-Startup $script:Injected "$point did not execute its reentrant stop."
            Assert-Startup ($script:BackgroundStarts -eq 1) 'The stop handler did not dispatch exactly once.'
            Assert-Startup ($script:ProcessStarts.Count -eq 0) "$kind at $point launched a process after cancellation (completed=$complete)."
            Assert-Startup ($script:LaunchState -eq 'idle') 'Cancelled model startup resumed polling.'
            if(-not $complete){Assert-Startup (-not $PrimaryButton.IsEnabled) 'Startup re-enabled its button while stop was active.'}
            $cases++
        }
    }
    foreach($complete in @($false,$true)){
        Reset-StartupFixture $point 'harness' $complete
        Start-UnifiedStack
        Assert-Startup $script:Injected "$point did not execute Close Harness."
        Assert-Startup ($script:ProcessStarts.Count -eq 1 -and $script:ProcessStarts[0] -like '*llama-server.exe') 'Close Harness interrupted model loading.'
        $owner=$script:TextGenOwnership
        Assert-Startup $script:SuppressHarnessStart 'Close Harness did not suppress the deferred Harness launch.'
        # Finish a pending stop, then run the actual ready-model poll.
        $script:StopOperation.Active=$false
        Set-FixtureRuntimeSnapshot
        Poll-Launch
        Assert-Startup ($script:ProcessStarts.Count -eq 1) 'The ready-model poll reopened Harness after Close Harness.'
        Assert-Startup ($script:LaunchState -eq 'idle' -and $script:TextGenOwnership -eq $owner) 'Close Harness lost the model or left startup pending.'
        $cases++
    }
}

# Closing during Harness preparation must also hold after the stop has already
# completed. This exercises Start-Harness itself, not a mocked replacement.
foreach($kind in @('harness','all')){
    foreach($complete in @($false,$true)){
        Reset-StartupFixture 'harness-preparation' $kind $complete
        Start-Harness
        Assert-Startup $script:Injected 'Harness preparation did not execute its reentrant stop.'
        Assert-Startup ($script:ProcessStarts.Count -eq 0) "$kind during Harness preparation reopened the service."
        $cases++
    }
}

# Positive control: the fixtures must allow an uninterrupted model and its
# deferred Harness launch, otherwise cancellation assertions could pass vacuously.
Reset-StartupFixture
Start-UnifiedStack
Set-FixtureRuntimeSnapshot
Poll-Launch
Assert-Startup ($script:ProcessStarts.Count -eq 2 -and $script:LaunchState -eq 'wait_harness') 'Uninterrupted startup no longer reaches model plus Harness launch.'
$cases++

# Reusing the same model name must not let the previous runtime's Ready sample
# complete a reload. Also reject a delayed old sample while awaiting Harness.
Reset-StartupFixture
Set-FixtureRuntimeSnapshot $true
$previousReady=$script:RuntimeSnapshot
Start-UnifiedStack
Assert-Startup ($null -eq $script:RuntimeSnapshot) 'A new launch retained the previous Ready snapshot.'
Assert-Startup ($script:StopOperation.Generation -gt $previousReady.StopGeneration) 'A new launch did not invalidate in-flight probes.'
$script:RuntimeSnapshot=$previousReady
Poll-Launch
Poll-Launch
Assert-Startup ($script:ProcessStarts.Count -eq 1 -and $script:LaunchState -eq 'wait_textgen' -and $script:LaunchPhase -ne 7) 'A previous-generation Ready sample opened Harness or completed model reload.'
$cases++
Set-FixtureRuntimeSnapshot
Poll-Launch
Assert-Startup ($script:ProcessStarts.Count -eq 2 -and $script:LaunchState -eq 'wait_harness') 'A fresh model sample did not advance startup.'
$script:RuntimeSnapshot=$previousReady
Poll-Launch
Assert-Startup ($script:LaunchState -eq 'wait_harness' -and $script:LaunchPhase -ne 7) 'A previous-generation Harness sample falsely marked startup Ready.'
Set-FixtureRuntimeSnapshot $true
Poll-Launch
Assert-Startup ($script:LaunchState -eq 'idle' -and $script:LaunchPhase -eq 7) 'A fresh Harness sample did not complete startup.'
$cases++
Write-Host "PASS: $cases production startup cases; Unload/Stop both cannot respawn a model; Close Harness preserves model loading and suppresses reopening; stale Ready samples are rejected; fresh snapshots complete startup."
