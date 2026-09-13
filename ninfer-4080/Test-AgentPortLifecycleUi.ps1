param([string]$RuntimePath=(Join-Path $PSScriptRoot '..\AgentPort-runtime-v1.7.0-4080.ps1'),[string]$PreviewPath='')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $RuntimePath),[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw ($parseErrors.Message -join '; ')}
$required=@('Set-StopControls','Update-AgentPortLifecycleControls','Open-HarnessFromHome','Start-AgentPortStopOperation','Complete-AgentPortStopOperationIfReady','Stop-BackendOnly','Stop-HarnessFromHome','Purge-AgentPortVram','Set-OperationFeedback')
$runtimeRoot=(Split-Path (Resolve-Path $RuntimePath)).Replace("'","''")
foreach($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    # Dynamic function extraction has no source filename, so restore its root.
    if($definition.Name -in $required){Invoke-Expression ($definition.Extent.Text.Replace('$PSScriptRoot',("'"+$runtimeRoot+"'")))}
}
$xamlNode=$ast.Find({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '<Window\s'},$true)
if(-not $xamlNode){throw 'Production Window XAML not found.'}
$window=[Windows.Markup.XamlReader]::Parse($xamlNode.Value)
foreach($name in @('StopBackendButton','StopHarnessButton','PurgeVramButton','RuntimeOpenUiButton','PrimaryButton','ModelControlStatus','HarnessControlStatus','OperationBanner','OperationTitle','OperationDetail','OperationProgress','OperationDot','LaunchProgressCard')){
    Set-Variable -Name $name -Value $window.FindName($name) -Scope Script
}
# Bind the production handlers, not copies of their routing logic.
foreach($statement in $ast.EndBlock.Statements){
    if($statement.Extent.Text -match '^\$(StopBackendButton|StopHarnessButton|PurgeVramButton|RuntimeOpenUiButton)\.Add_Click\('){Invoke-Expression $statement.Extent.Text}
}
function Assert-Ui($condition,[string]$message){if(-not $condition){throw $message}}
function Pump-Ui {$window.UpdateLayout()}
function Set-Log {}
function Refresh-Runtime {}
function Test-Port([int]$Port){return ($Port -eq 3080 -and $script:HarnessListener)}
function Get-HarnessStartupUrl {return 'http://127.0.0.1:3080'}
function Start-Harness {$script:HarnessStartCount++;$script:OpenedModel=$script:PendingModel}
function New-AgentPortBackgroundOperation {param($Name,$ScriptText,$Payload,$TimeoutSeconds);$script:LastPayload=$Payload;return [pscustomobject]@{Name=$Name}}
function Test-AgentPortBackgroundOperationTimedOut {return $script:TimedOut}
function Test-AgentPortBackgroundOperationCompleted {return $true}
function Stop-AgentPortBackgroundOperation {}
function Complete-AgentPortBackgroundOperation {return $script:StopResult}
function Click($button){$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
function Reset-Fixture {
    $script:LaunchState='idle';$script:TeamStarting=$false;$script:HarnessOnlyLaunch=$false;$script:ModelStopGeneration=0
    $script:StopOperation=[pscustomobject]@{Active=$false;Generation=0;Kind='';StartedAt=$null;Handle=$null}
    $script:RuntimeSnapshot=[pscustomobject]@{BackendOnline=$true;HarnessOnline=$true}
    $script:Config=@{active_model='active-model.gguf';active_context_tokens=49152;harness_root='fixture';textgen_root='fixture'}
    $script:BackendPort=15100;$script:AppDataDir=$PSScriptRoot;$script:NpmCacheDir=$PSScriptRoot;$script:PortableNodeDir=$PSScriptRoot
    $script:NInferState=$null;$script:TextGenProcess='model-process';$script:HarnessProcess='harness-process'
    $script:TextGenOwnership='model-owner';$script:HarnessOwnership='harness-owner'
    $script:HarnessListener=$true;$script:OpenHarnessWhenReady=$false;$script:HarnessStartCount=0;$script:TimedOut=$false
    $script:StopResult=[pscustomobject]@{StoppedPids=@(123);SkippedPids=@();UnownedListenerPids=@();RemainingListenerPids=@();FailedPids=@();RemainingOwnedPids=@();FailureDetails=@()}
}
try {
    foreach($model in @($false,$true)){foreach($harness in @($false,$true)){
        Reset-Fixture;Update-AgentPortLifecycleControls $model $harness
        Assert-Ui $StopBackendButton.IsEnabled 'Unload must remain available for orphaned runtimes.'
        Assert-Ui $RuntimeOpenUiButton.IsEnabled 'Harness must be openable with or without a model.'
        Assert-Ui ($RuntimeOpenUiButton.Content -eq $(if($harness){'Show Harness'}else{'Open Harness'})) 'Wrong Harness action.'
    }}
    Reset-Fixture;$script:LaunchState='wait_harness';Click $StopBackendButton
    Assert-Ui ($script:StopOperation.Kind -eq 'backend' -and $script:LaunchState -eq 'idle') ('Unload routing/startup cancellation failed. '+$OperationDetail.Text)
    Assert-Ui (-not $PrimaryButton.IsEnabled -and $StopBackendButton.Content -eq 'Unloading...') 'Missing immediate busy feedback.'
    Complete-AgentPortStopOperationIfReady
    Assert-Ui ($null -eq $script:TextGenOwnership -and $script:HarnessOwnership -eq 'harness-owner') 'Unload changed Harness ownership.'
    Assert-Ui ($null -eq $script:RuntimeSnapshot) 'Unload retained a stale model Ready state.'
    Assert-Ui ($OperationTitle.Text -eq 'Model unloaded') 'Unload did not confirm success.'
    Reset-Fixture;Click $StopHarnessButton;Complete-AgentPortStopOperationIfReady
    Assert-Ui ($null -eq $script:HarnessOwnership -and $script:TextGenOwnership -eq 'model-owner') 'Close Harness changed model ownership.'
    $script:HarnessListener=$false;Update-AgentPortLifecycleControls $true $false;Click $RuntimeOpenUiButton
    Assert-Ui ($script:HarnessStartCount -eq 1 -and $script:OpenedModel -eq 'active-model.gguf') 'Reopen must use active model, not dropdown.'
    Assert-Ui ($script:TextGenProcess -eq 'model-process' -and $script:HarnessOnlyLaunch) 'Reopen interrupted model.'
    Reset-Fixture;Click $PurgeVramButton;Complete-AgentPortStopOperationIfReady
    Assert-Ui ($null -eq $script:HarnessOwnership -and $null -eq $script:TextGenOwnership) 'Stop both incomplete.'
    Reset-Fixture;$script:StopResult.FailedPids=@(456);Click $StopHarnessButton;Complete-AgentPortStopOperationIfReady
    Assert-Ui ($OperationTitle.Text -eq 'Stop failed' -and $script:HarnessOwnership -eq 'harness-owner') 'Failed stop claimed success or lost ownership.'
    Reset-Fixture;$script:StopResult=$null;Click $StopBackendButton;Complete-AgentPortStopOperationIfReady
    Assert-Ui ($OperationTitle.Text -eq 'Stop failed') 'Missing worker result claimed success.'
    Reset-Fixture;Click $StopBackendButton;$script:TimedOut=$true;Complete-AgentPortStopOperationIfReady
    Assert-Ui ($OperationTitle.Text -eq 'Stop timed out' -and $script:HarnessOwnership -eq 'harness-owner') 'Timeout handling failed.'
    Reset-Fixture;Update-AgentPortLifecycleControls $false $true
    $OperationBanner.Visibility='Collapsed'
    # Render the actual control group at the minimum supported content width.
    $controlGroup=$ModelControlStatus.Parent.Parent.Parent
    while($controlGroup -and -not ($controlGroup -is [Windows.Controls.Border])){$controlGroup=$controlGroup.Parent}
    if($PreviewPath -and $controlGroup){
        $controlGroup.Measure([Windows.Size]::new(850,[double]::PositiveInfinity))
        $controlGroup.Arrange([Windows.Rect]::new(0,0,850,$controlGroup.DesiredSize.Height));$controlGroup.UpdateLayout()
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(850,[int][math]::Ceiling($controlGroup.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($controlGroup);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create($PreviewPath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
    Write-Host 'PASS: production Home XAML + all four lifecycle states; real button handlers; independent ownership; reopen; busy feedback; failure and timeout recovery.'
} finally {$window.Close()}
