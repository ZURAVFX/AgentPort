. (Join-Path $PSScriptRoot 'AgentPort.AutoContinue.ps1')

function Resolve-AgentPortMcpCommand {
    param([string]$Command)
    if(-not $Command -or $Command -notin @('comfy-mcp','blender-mcp')){return $Command}
    $kind=if($Command -eq 'comfy-mcp'){'comfy'}else{'blender'}
    $managed=Join-Path $env:LOCALAPPDATA "AgentPort\mcp\$kind\Scripts\$Command.exe"
    if(Test-Path $managed){return $managed}
    $found=Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
    if($found -and $found.Source){return [string]$found.Source}
    $candidates=switch($Command){
        'comfy-mcp' {@(
            (Join-Path $env:USERPROFILE '.codex\mcp\comfy-mcp\Scripts\comfy-mcp.exe'),
            (Join-Path $env:USERPROFILE '.codex\mcp\comfy-mcp\Scripts\comfy-mcp.cmd')
        )}
        'blender-mcp' {@(
            (Join-Path $env:USERPROFILE '.codex\tools\blender-official\mcp\.venv\Scripts\blender-mcp.exe'),
            (Join-Path $env:USERPROFILE '.codex\tools\blender-official\mcp\.venv\Scripts\blender-mcp.cmd')
        )}
    }
    foreach($candidate in @($candidates)){if(Test-Path -LiteralPath $candidate){return (Resolve-Path -LiteralPath $candidate).Path}}
    return $Command
}

function Test-AgentPortMcpCommandAvailable {
    param([string]$Command)
    $resolved=Resolve-AgentPortMcpCommand $Command
    if([IO.Path]::IsPathRooted($resolved)){return Test-Path -LiteralPath $resolved}
    return $null -ne (Get-Command $resolved -ErrorAction SilentlyContinue)
}

function Get-AgentPortMcpSettings {
    $path=Join-Path $script:ConfigDir 'agentport-mcp.json'
    if(Test-Path $path){$settings=Get-Content $path -Raw | ConvertFrom-Json}else{$settings=[pscustomobject]@{useWithNInfer=$true;servers=@()}}
    foreach($server in @($settings.servers)){
        if($server.config -and $server.config.transport -eq 'stdio'){
            $server.config.command=Resolve-AgentPortMcpCommand ([string]$server.config.command)
            $server.config.failOnStartupError=$false
        }
    }
    return $settings
}

function Repair-AgentPortMcpSettings {
    # Migrate earlier AgentPort installs which used the old connector directly.
    # Keep a user's enabled/disabled choices, except that a locally installed
    # official Blender connector is safe to restore when it was disabled by an
    # old failed setup attempt.
    $path=Join-Path $script:ConfigDir 'agentport-mcp.json'
    if(-not(Test-Path $path)){return}
    $settings=Get-AgentPortMcpSettings
    $changed=$false
    $comfy=@($settings.servers | Where-Object {$_.name -eq 'comfy-mcp'} | Select-Object -First 1)
    if($comfy){
        $detected=Find-AgentPortComfy
        $url=if($detected.Url){$detected.Url}else{'http://127.0.0.1:8188'}
        $command=Resolve-AgentPortMcpCommand 'comfy-mcp'
        if(Test-AgentPortMcpCommandAvailable 'comfy-mcp'){
            $comfy[0].enabled=$true
            $comfy[0].config=[pscustomobject]@{serverName='comfy-mcp';transport='stdio';command=$command;args=@();env=@{COMFY_BIN=(Join-Path (Split-Path $command) 'comfy.exe');COMFY_LOCAL_URL=$url;PYTHONUTF8='1';PYTHONIOENCODING='utf-8'};toolCallTimeoutMs=180000;failOnStartupError=$false}
            $changed=$true
        }
    }
    $blender=@($settings.servers | Where-Object {$_.name -eq 'blender-mcp'} | Select-Object -First 1)
    if($blender -and (Test-AgentPortMcpCommandAvailable 'blender-mcp')){
        $command=Resolve-AgentPortMcpCommand 'blender-mcp'
        $blender[0].enabled=$true
        $blender[0].config=[pscustomobject]@{serverName='blender-mcp';transport='stdio';command=$command;args=@();env=@{PYTHONUTF8='1';PYTHONIOENCODING='utf-8'};toolCallTimeoutMs=180000;failOnStartupError=$false}
        $changed=$true
    }
    if($changed){
        Copy-Item -LiteralPath $path -Destination ($path+'.bak') -Force
        [IO.File]::WriteAllText($path,($settings | ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    }
}

function Invoke-AgentPortMcpInstall {
    param([string]$Tool)
    $logRoot=Join-Path $env:LOCALAPPDATA 'AgentPort\mcp'
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $log=Join-Path $logRoot ('install-'+$Tool)
    $p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Install-Mcp.ps1')+'"'),'-Tool',$Tool) -WindowStyle Hidden -PassThru -RedirectStandardOutput ($log+'.out.log') -RedirectStandardError ($log+'.err.log')
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(-not $p.HasExited){
        if($timer.Elapsed.TotalMinutes -gt 10){& taskkill.exe /PID $p.Id /T /F | Out-Null;throw "Installation timed out. Check $log.err.log and retry."}
        [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100;$p.Refresh()
    }
    if($p.ExitCode -ne 0){throw "Installation failed. See $log.err.log for the download error, then retry."}
}

function Find-AgentPortComfy {
    $workspace='';$url='http://127.0.0.1:8188'
    foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue)){
        if($process.CommandLine -notmatch 'main.py' -or $process.CommandLine -notmatch 'ComfyUI'){continue}
        if($process.CommandLine -match '--port\s+(\d+)'){$url='http://127.0.0.1:'+$Matches[1]}
        if($process.ExecutablePath -match '^(.*)[\\/]\.venv[\\/]Scripts[\\/]python.exe$'){$workspace=$Matches[1]}
        if($workspace -and (Test-Path (Join-Path $workspace 'main.py'))){break}
    }
    return [pscustomobject]@{Workspace=$workspace;Url=$url}
}

function Test-AgentPortMcpConnection {
    param($Config,[string]$Probe='')
    $python=Join-Path $env:LOCALAPPDATA 'AgentPort\mcp\checker\Scripts\python.exe'
    if(-not(Test-Path $python)){Invoke-AgentPortMcpInstall 'checker'}
    $copy=$Config | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    if($Probe){$copy | Add-Member -NotePropertyName probe -NotePropertyValue $Probe -Force}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$python
    $info.Arguments='"'+(Join-Path $PSScriptRoot 'mcp-check.py')+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
    $p=[Diagnostics.Process]::Start($info)
    try{
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        $p.StandardInput.WriteLine(($copy | ConvertTo-Json -Depth 15 -Compress));$p.StandardInput.Close()
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while(-not $p.HasExited){
            if($timer.Elapsed.TotalSeconds -gt 75){& taskkill.exe /PID $p.Id /T /F | Out-Null;throw 'Connection timed out. Check the app is running and its address is correct.'}
            [Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100;$p.Refresh()
        }
        $result=$stdout.Result | ConvertFrom-Json
        if(-not $result.connected){throw "MCP could not connect: $($result.error)"}
        if($Probe -and -not $result.applicationOk){throw "MCP is installed, but the app did not respond: $($result.reply -join ' ')"}
        if($Probe -eq 'server_info'){
            $details=$result.reply[0] | ConvertFrom-Json
            if(-not $details.server.running){throw 'ComfyUI is not reachable. Open ComfyUI and check its address above.'}
            $url=if($Config.env.COMFY_LOCAL_URL){$Config.env.COMFY_LOCAL_URL}else{$details.server.url}
            try{$queue=Invoke-RestMethod ($url.TrimEnd('/')+'/queue') -TimeoutSec 5;if($null -eq $queue.queue_running){throw 'Unexpected queue response'}}catch{throw 'ComfyUI has an open port but its API is not responding. Restart ComfyUI, then test again. Check custom nodes and disconnected model folders if it happens again.'}
        }
        return $result
    }finally{$p.Dispose()}
}

function Convert-AgentPortMcpImport {
    param([string]$Json)
    $document=$Json | ConvertFrom-Json
    $serverDocument=if($document.mcpServers){$document.mcpServers}elseif($document.servers){$document.servers}else{$null}
    if(-not $serverDocument){throw 'Paste a JSON configuration containing mcpServers.'}
    $servers=@()
    foreach($property in $serverDocument.PSObject.Properties){
        $name=$property.Name; $value=$property.Value
        if($name -notmatch '^[A-Za-z0-9_-]{1,32}$'){throw "Invalid server name: $name"}
        $config=[ordered]@{serverName=$name;toolCallTimeoutMs=60000;failOnStartupError=$true}
        $serverUrl=if($value.url){[string]$value.url}elseif($value.serverUrl){[string]$value.serverUrl}else{$null}
        if($value.type -eq 'sse' -or $value.transport -eq 'sse'){throw 'This Harness supports Streamable HTTP, not legacy SSE. Ask the MCP publisher for a Streamable HTTP URL or stdio command.'}
        if($serverUrl){
            $uri=$null
            if(-not [Uri]::TryCreate($serverUrl,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Server URL must use http or https.'}
            $config.transport='streamable-http';$config.url=$serverUrl
            if($value.headers){$config.headers=$value.headers}
        } else {
            if(-not $value.command){throw "Server $name needs a command or URL."}
            if($value.args -is [string]){throw 'args must be a JSON array of strings.'}
            $arguments=@();if($null -ne $value.args){foreach($arg in @($value.args)){if($arg -isnot [string]){throw 'Every argument must be a string.'};$arguments+=$arg}}
            $config.transport='stdio';$config.command=[string]$value.command;$config.args=$arguments
            if($value.env){$config.env=$value.env}
            if($value.cwd){$config.cwd=[string]$value.cwd}
        }
        $servers+=[pscustomobject]@{name=$name;enabled=$true;config=$config}
    }
    return $servers
}

function Write-AgentPortMcpOverlay {
    param([string]$Path,[switch]$NInfer,[switch]$ForceDisableNInfer)
    $settings=Get-AgentPortMcpSettings
    $entries=@()
    if(-not $ForceDisableNInfer){
        foreach($server in @($settings.servers)){
            if($server.enabled){
                $entryConfig=[ordered]@{};foreach($key in $server.config.PSObject.Properties.Name){$entryConfig[$key]=$server.config.$key}
                $checker=Join-Path $env:LOCALAPPDATA 'AgentPort\mcp\checker\Scripts\python.exe'
                if($settings.fullCatalog -ne $true -and $entryConfig.transport -eq 'stdio' -and $server.name -in @('comfy-mcp','blender-mcp') -and (Test-Path $checker)){
                    $allowed=if($server.name -eq 'comfy-mcp'){@('server_info','system_stats','search_models','nodes','search_templates','fetch_template','get_template','run_workflow','validate_workflow','job','fetch_outputs','upload_file','free_memory')}else{@('execute_blender_code','get_objects_summary','get_blendfile_summary_datablocks','get_python_api_docs','get_screenshot_of_area_as_image')}
                    $upstream=[ordered]@{};foreach($key in $entryConfig.Keys){$upstream[$key]=$entryConfig[$key]};$upstream.allowedTools=$allowed
                    $entryConfig.command=$checker;$entryConfig.args=@((Join-Path $PSScriptRoot 'mcp-tools.py'))
                    $entryConfig.env=@{AGENTPORT_MCP_UPSTREAM=($upstream | ConvertTo-Json -Depth 15 -Compress);PYTHONIOENCODING='utf-8'}
                }
                $entryConfig.failOnStartupError=$false;$entries+=@{id=('agentport-mcp-'+$server.name);name='@deepseek-ai/dsh-mcp-client';config=$entryConfig}
            }
        }
    }
    $entries+=@{id='agentport-auto-continue';name=(Join-Path $PSScriptRoot 'AgentPort.AutoContinue.js');config=@{settingsPath=(Get-AgentPortAutoContinuePath)}}
    $json=ConvertTo-Json -InputObject @(@{insert=$entries}) -Depth 15
    [IO.File]::WriteAllText($Path,$json,[Text.UTF8Encoding]::new($false))
    return $Path
}

function Show-AgentPortMcpManager {
    param([switch]$SmokeTest)
    [xml]$layout=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="MCP connections" Width="780" Height="820" MinWidth="720" MinHeight="720" WindowStartupLocation="CenterOwner" Background="#090C11" Foreground="White" FontFamily="Segoe UI">
<Window.Resources><Style TargetType="Button"><Setter Property="Background" Value="#191D26"/><Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="BorderBrush" Value="#343946"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="14,9"/><Setter Property="Cursor" Value="Hand"/></Style><Style TargetType="TextBox"><Setter Property="Background" Value="#10141B"/><Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="BorderBrush" Value="#343946"/><Setter Property="CaretBrush" Value="White"/><Setter Property="Padding" Value="10"/></Style></Window.Resources>
<Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<StackPanel><TextBlock Text="MCP connections" FontSize="25" FontWeight="SemiBold"/><TextBlock Text="Connect trusted tools to DeepSeek Harness. Changes apply the next time Harness starts." Foreground="#9A9AA5" Margin="0,5,0,18"/></StackPanel>
<Border Grid.Row="1" Background="#0C1711" BorderBrush="#245E38" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,0,12"><StackPanel><TextBlock Text="Connect an app" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="AgentPort installs the MCP connector for you. Leave the app running." Foreground="#B3DCC0" FontSize="12" Margin="0,4,0,10"/>
<TextBlock Text="ComfyUI address (from its browser tab)"/><TextBox x:Name="ComfyUrl" Text="http://127.0.0.1:8188" Margin="0,5,0,8"/>
<TextBlock Text="ComfyUI installation folder (containing main.py)"/><TextBox x:Name="ComfyPath" Margin="0,5,0,8"/>
<WrapPanel><Button x:Name="Comfy" Content="Install &amp; connect ComfyUI" Background="#6546E8" BorderBrush="#8068F3" Margin="0,0,8,8"/><Button x:Name="Blender" Content="Install &amp; connect Blender" Background="#6546E8" BorderBrush="#8068F3" Margin="0,0,8,8"/><Button x:Name="BlenderHelp" Content="Blender add-on setup" Margin="0,0,0,8"/></WrapPanel>
<TextBlock Text="Blender 5.1+: install the official Lab MCP add-on, then enable it in Edit > Preferences > Add-ons. Start its server there. AgentPort installs the matching connector." TextWrapping="Wrap" Foreground="#B3DCC0" FontSize="12"/>
</StackPanel></Border>
<Expander Grid.Row="2" Header="Add another MCP (paste configuration, no folder needed)" Foreground="#D1D1D6" Margin="0,0,0,12"><StackPanel Margin="0,10,0,0"><TextBlock Text="Copy the publisher's mcpServers JSON: a command with args, or a Streamable HTTP url. Include required env / headers. A website link alone is not an MCP address. npx commands need Node.js; uvx commands need uv." TextWrapping="Wrap" Foreground="#B8B8C2" FontSize="12" Margin="0,0,0,7"/><TextBox x:Name="Input" Height="90" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas"/><WrapPanel><Button x:Name="Import" Content="Add from JSON" Margin="0,8,8,0"/><Button x:Name="Template" Content="Connect a filesystem folder" Margin="0,8,0,0"/></WrapPanel><CheckBox x:Name="FullCatalog" Content="Expose all ComfyUI / Blender tools (slower; default is the everyday tool set)" Foreground="White" Margin="0,10,0,0"/></StackPanel></Expander>
<Border Grid.Row="3" Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="14" Padding="16"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="Enabled connections" FontSize="15" FontWeight="SemiBold"/><ScrollViewer Grid.Row="1" Margin="0,10,0,10" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Servers"/></ScrollViewer><TextBlock Grid.Row="2" Text="Checked tools are available with either backend after restarting Harness. No matching skill is required. Enable only the tools you need to save context." TextWrapping="Wrap" Foreground="#B8B8C2" FontSize="12"/></Grid></Border>
<Grid Grid.Row="4" Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="Status" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="#F1C66D" Margin="0,0,12,0"/><Button x:Name="Save" Grid.Column="1" Content="Save"/><Button x:Name="Restart" Grid.Column="2" Content="Save &amp; restart Harness" Background="#6546E8" BorderBrush="#8068F3" Margin="8,0,0,0"/></Grid>
</Grid></Window>
'@
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout));$dialog.Owner=$Window
    $settings=Get-AgentPortMcpSettings
    $dialog.FindName('FullCatalog').IsChecked=($settings.fullCatalog -eq $true)
    $inputBox=$dialog.FindName('Input');$panel=$dialog.FindName('Servers');$status=$dialog.FindName('Status')
    $detected=Find-AgentPortComfy
    $savedComfy=@($settings.servers | Where-Object name -eq 'comfy-mcp' | Select-Object -First 1)
    if(-not $detected.Workspace -and $savedComfy){
        if($savedComfy[0].config.env.COMFY_LOCAL_URL){$detected.Url=$savedComfy[0].config.env.COMFY_LOCAL_URL}
        if($savedComfy[0].config.env.COMFY_PROJECT){$detected.Workspace=$savedComfy[0].config.env.COMFY_PROJECT}
    }
    $dialog.FindName('ComfyUrl').Text=$detected.Url;$dialog.FindName('ComfyPath').Text=$detected.Workspace
    $busy=[pscustomobject]@{Value=$false}
    $dialog.Add_Closing({param($s,$e)if($busy.Value){$e.Cancel=$true;$status.Text='Wait for the current connection check or installation to finish.'}})
    $refresh={
        $panel.Children.Clear()
        if(@($settings.servers).Count -eq 0){$empty=[Windows.Controls.TextBlock]::new();$empty.Text='No MCP connections yet.';$empty.Foreground='#777788';$empty.Margin='2,8,0,0';[void]$panel.Children.Add($empty);return}
        foreach($server in @($settings.servers)){
            $row=[Windows.Controls.Grid]::new();$row.Margin='0,0,0,8';$row.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$auto=[Windows.Controls.ColumnDefinition]::new();$auto.Width='Auto';$row.ColumnDefinitions.Add($auto)
            $check=[Windows.Controls.CheckBox]::new();$check.Content=$server.name;$check.Foreground=[Windows.Media.Brushes]::White;$check.IsChecked=[bool]$server.enabled;$check.Tag=$server;$check.VerticalAlignment='Center';[void]$row.Children.Add($check)
            $check.Add_Checked({param($s,$e)$s.Tag.enabled=$true});$check.Add_Unchecked({param($s,$e)$s.Tag.enabled=$false})
            $actions=[Windows.Controls.StackPanel]::new();$actions.Orientation='Horizontal'
            $test=[Windows.Controls.Button]::new();$test.Content='Test';$test.Tag=$server;$test.Padding='10,5';$test.Margin='0,0,6,0'
            $test.Add_Click({param($s,$e)
                if($busy.Value){return};$busy.Value=$true;$status.Text='Checking MCP and app connection...'
                try{$probe=switch($s.Tag.name){'comfy-mcp'{'server_info'}'blender-mcp'{'get_blendfile_summary_datablocks'}default{''}}
                    $result=Test-AgentPortMcpConnection $s.Tag.config $probe;$status.Text="$($s.Tag.name): connected, $($result.count) tools available. Restart Harness after saving."
                }catch{$status.Text=$_.Exception.Message}finally{$busy.Value=$false}
            });[void]$actions.Children.Add($test)
            $remove=[Windows.Controls.Button]::new();$remove.Content='Remove';$remove.Tag=[string]$server.name;$remove.Padding='10,5';$remove.Add_Click({param($s,$e)if($busy.Value){return};$settings.servers=@($settings.servers | Where-Object {$_.name -ne [string]$s.Tag}); & $refresh});[void]$actions.Children.Add($remove);[Windows.Controls.Grid]::SetColumn($actions,1);[void]$row.Children.Add($actions);[void]$panel.Children.Add($row)
        }
    }
    & $refresh
    $dialog.FindName('Comfy').Add_Click({
        if($busy.Value){return};$busy.Value=$true
        try{
            $workspace=$dialog.FindName('ComfyPath').Text.Trim();$url=$dialog.FindName('ComfyUrl').Text.Trim().TrimEnd('/')
            if(-not $workspace){$folder=[Windows.Forms.FolderBrowserDialog]::new();$folder.Description='Select ComfyUI (the folder containing main.py)';if($folder.ShowDialog() -ne 'OK'){return};$workspace=$folder.SelectedPath;$dialog.FindName('ComfyPath').Text=$workspace}
            if(-not(Test-Path (Join-Path $workspace 'main.py'))){throw 'Choose the ComfyUI folder containing main.py, often one level inside the portable folder.'}
            $uri=$null;if(-not[Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or -not $uri.IsLoopback){throw 'Enter the local ComfyUI address, for example http://127.0.0.1:8188.'}
            $status.Text='Installing ComfyUI connector. First download may take a few minutes...'
            Invoke-AgentPortMcpInstall 'comfy'
            $command=Resolve-AgentPortMcpCommand 'comfy-mcp';$cli=Join-Path (Split-Path $command) 'comfy.exe'
            $env:PYTHONIOENCODING='utf-8';$env:PYTHONUTF8='1'
            & $cli --skip-prompt set-default $workspace | Out-Null
            if($LASTEXITCODE){throw 'Could not set the ComfyUI workspace. Check the selected folder.'}
            $config=[pscustomobject]@{serverName='comfy-mcp';transport='stdio';command=$command;args=@();env=@{COMFY_BIN=$cli;COMFY_LOCAL_URL=$url;PYTHONUTF8='1';PYTHONIOENCODING='utf-8'};toolCallTimeoutMs=180000;failOnStartupError=$false}
            $settings.servers=@($settings.servers | Where-Object name -ne 'comfy-mcp')+[pscustomobject]@{name='comfy-mcp';enabled=$true;config=$config}
            & $refresh;& $save;$status.Text='Checking the running ComfyUI...'
            $result=Test-AgentPortMcpConnection $config 'server_info'
            $status.Text="ComfyUI connected: $($result.count) tools. Click Save & restart Harness, then ask it to inspect your models."
        }catch{$status.Text=$_.Exception.Message}finally{$busy.Value=$false}
    })
    $dialog.FindName('Blender').Add_Click({
        if($busy.Value){return};$busy.Value=$true
        try{
            $status.Text='Installing the official Blender connector...';Invoke-AgentPortMcpInstall 'blender'
            $config=[pscustomobject]@{serverName='blender-mcp';transport='stdio';command=(Resolve-AgentPortMcpCommand 'blender-mcp');args=@();env=@{PYTHONUTF8='1';PYTHONIOENCODING='utf-8'};toolCallTimeoutMs=180000;failOnStartupError=$false}
            $settings.servers=@($settings.servers | Where-Object name -ne 'blender-mcp')+[pscustomobject]@{name='blender-mcp';enabled=$true;config=$config}
            & $refresh;& $save;$status.Text='Checking Blender. Open Blender and enable the Lab MCP add-on...'
            $result=Test-AgentPortMcpConnection $config 'get_blendfile_summary_datablocks'
            $status.Text="Blender connected: $($result.count) tools. Click Save & restart Harness, then ask it to inspect your scene."
        }catch{$status.Text='Blender connection needs attention. Open Blender > Edit > Preferences > Add-ons > MCP and start its server. '+$_.Exception.Message}finally{$busy.Value=$false}
    })
    $dialog.FindName('BlenderHelp').Add_Click({Start-Process 'https://www.blender.org/lab/mcp-server/'})
    $dialog.FindName('Template').Add_Click({
        $folder=[Windows.Forms.FolderBrowserDialog]::new()
        if($folder.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
            $inputBox.Text=@{mcpServers=@{filesystem=@{command='npx';args=@('-y','@modelcontextprotocol/server-filesystem',$folder.SelectedPath)}}}|ConvertTo-Json -Depth 6
        }
    })
    $dialog.FindName('Import').Add_Click({try {
        $added=@(Convert-AgentPortMcpImport $inputBox.Text)
        $settings.servers=@($settings.servers | Where-Object {$_.name -notin $added.name})+$added
        & $refresh;$status.Text='Added. Review the connection, then save.'
    } catch {$status.Text=$_.Exception.Message}})
    $save={
        foreach($row in $panel.Children){if($row -is [Windows.Controls.Grid]){$check=$row.Children[0];$check.Tag.enabled=[bool]$check.IsChecked}}
        $settings.useWithNInfer=$true
        $settings | Add-Member -NotePropertyName fullCatalog -NotePropertyValue ([bool]$dialog.FindName('FullCatalog').IsChecked) -Force
        Ensure-ConfigDir
        $path=Join-Path $script:ConfigDir 'agentport-mcp.json'
        if(Test-Path $path){Copy-Item $path ($path+'.bak') -Force}
        [IO.File]::WriteAllText($path,($settings|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
        $status.Text='Saved. Start or restart Harness to connect these tools.'
    }
    $dialog.FindName('Save').Add_Click({try {& $save}catch{$status.Text=$_.Exception.Message}})
    $dialog.FindName('Restart').Add_Click({try {
        & $save
        if(-not $script:PendingModel){throw 'Choose and start a model first.'}
        Kill-HarnessOnly
        Start-Sleep -Milliseconds 700
        if(Test-Port 3080){throw 'An externally started Harness is using port 3080. Close it before restarting.'}
        if($script:NInferState){$script:NInferHarnessPatch=New-NInferHarnessPatch (Join-Path $script:NInferState.LogDirectory 'coding.patch.yml')}
        Start-Harness;$status.Text='Harness is restarting. Connection failures appear in the Harness log.'
    } catch {$status.Text=$_.Exception.Message}})
    if($SmokeTest){$dialog.Add_ContentRendered({Write-Host 'MCP manager rendered';Save-AgentPortPreview $dialog 'mcp';$dialog.Close()})}
    [void]$dialog.ShowDialog()
}
