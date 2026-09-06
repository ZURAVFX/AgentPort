function Get-AgentPortMcpSettings {
    $path=Join-Path $script:ConfigDir 'agentport-mcp.json'
    if(Test-Path $path){return Get-Content $path -Raw | ConvertFrom-Json}
    return [pscustomobject]@{useWithNInfer=$false;servers=@()}
}

function Convert-AgentPortMcpImport {
    param([string]$Json)
    $document=$Json | ConvertFrom-Json
    if(-not $document.mcpServers){throw 'Paste a JSON configuration containing mcpServers.'}
    $servers=@()
    foreach($property in $document.mcpServers.PSObject.Properties){
        $name=$property.Name; $value=$property.Value
        if($name -notmatch '^[A-Za-z0-9_-]{1,32}$'){throw "Invalid server name: $name"}
        $config=[ordered]@{serverName=$name;toolCallTimeoutMs=60000;failOnStartupError=$true}
        if($value.url){
            $uri=$null
            if(-not [Uri]::TryCreate([string]$value.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')){throw 'Server URL must use http or https.'}
            $config.transport='streamable-http';$config.url=[string]$value.url
            if($value.headers){$config.headers=$value.headers}
        } else {
            if(-not $value.command){throw "Server $name needs a command or URL."}
            if($value.args -is [string]){throw 'args must be a JSON array of strings.'}
            foreach($arg in @($value.args)){if($arg -isnot [string]){throw 'Every argument must be a string.'}}
            $config.transport='stdio';$config.command=[string]$value.command;$config.args=@($value.args)
            if($value.env){$config.env=$value.env}
            if($value.cwd){$config.cwd=[string]$value.cwd}
        }
        $servers+=[pscustomobject]@{name=$name;enabled=$true;config=$config}
    }
    return $servers
}

function Write-AgentPortMcpOverlay {
    param([string]$Path,[switch]$NInfer)
    $settings=Get-AgentPortMcpSettings
    $entries=@()
    if(-not $NInfer -or $settings.useWithNInfer){
        foreach($server in @($settings.servers)){
            if($server.enabled){$entries+=@{id=('agentport-mcp-'+$server.name);name='@deepseek-ai/dsh-mcp-client';config=$server.config}}
        }
    }
    $json=if($entries.Count){ConvertTo-Json -InputObject @(@{insert=$entries}) -Depth 15}else{'[]'}
    [IO.File]::WriteAllText($Path,$json,[Text.UTF8Encoding]::new($false))
    return $Path
}

function Show-AgentPortMcpManager {
    param([switch]$SmokeTest)
    [xml]$layout=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="MCP connections" Width="720" Height="680" MinWidth="620" MinHeight="580" WindowStartupLocation="CenterOwner" Background="#090C11" Foreground="White" FontFamily="Segoe UI">
<Window.Resources><Style TargetType="Button"><Setter Property="Background" Value="#191D26"/><Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="BorderBrush" Value="#343946"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="14,9"/><Setter Property="Cursor" Value="Hand"/></Style><Style TargetType="TextBox"><Setter Property="Background" Value="#10141B"/><Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="BorderBrush" Value="#343946"/><Setter Property="CaretBrush" Value="White"/><Setter Property="Padding" Value="10"/></Style></Window.Resources>
<Grid Margin="24"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<StackPanel><TextBlock Text="MCP connections" FontSize="25" FontWeight="SemiBold"/><TextBlock Text="Connect trusted tools to DeepSeek Harness. Changes apply the next time Harness starts." Foreground="#9A9AA5" Margin="0,5,0,18"/></StackPanel>
<Border Grid.Row="1" Background="#0C1711" BorderBrush="#245E38" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,0,0,12"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="Give Harness access to a folder" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="Choose a folder. AgentPort creates the connection for you." Foreground="#9BC9A8" FontSize="11" Margin="0,4,12,0"/></StackPanel><Button x:Name="Template" Grid.Column="1" Content="Choose folder" Background="#6546E8" BorderBrush="#8068F3"/></Grid></Border>
<Expander Grid.Row="2" Header="Import an MCP configuration" Foreground="#D1D1D6" Margin="0,0,0,12"><StackPanel Margin="0,10,0,0"><TextBlock Text="Paste standard JSON containing mcpServers." Foreground="#92929B" FontSize="11" Margin="0,0,0,7"/><TextBox x:Name="Input" Height="120" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas"/><Button x:Name="Import" Content="Add from JSON" HorizontalAlignment="Left" Margin="0,8,0,0"/></StackPanel></Expander>
<Border Grid.Row="3" Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="14" Padding="16"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock Text="Connected tools" FontSize="15" FontWeight="SemiBold"/><ScrollViewer Grid.Row="1" Margin="0,10,0,10" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Servers"/></ScrollViewer><StackPanel Grid.Row="2"><CheckBox x:Name="Local" Content="Enable MCP tools while using NInfer" Foreground="White"/><TextBlock Text="Leave this off for maximum NInfer speed and context. Local MCP commands run on your PC, so only connect tools you trust." TextWrapping="Wrap" Foreground="#8A8A94" FontSize="11" Margin="0,5,0,0"/></StackPanel></Grid></Border>
<Grid Grid.Row="4" Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="Status" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="#F1C66D" Margin="0,0,12,0"/><Button x:Name="Save" Grid.Column="1" Content="Save"/><Button x:Name="Restart" Grid.Column="2" Content="Save &amp; restart Harness" Background="#6546E8" BorderBrush="#8068F3" Margin="8,0,0,0"/></Grid>
</Grid></Window>
'@
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout));$dialog.Owner=$Window
    $settings=Get-AgentPortMcpSettings
    $inputBox=$dialog.FindName('Input');$panel=$dialog.FindName('Servers');$status=$dialog.FindName('Status');$local=$dialog.FindName('Local')
    $local.IsChecked=[bool]$settings.useWithNInfer
    $refresh={
        $panel.Children.Clear()
        if(@($settings.servers).Count -eq 0){$empty=[Windows.Controls.TextBlock]::new();$empty.Text='No MCP connections yet.';$empty.Foreground='#777788';$empty.Margin='2,8,0,0';[void]$panel.Children.Add($empty);return}
        foreach($server in @($settings.servers)){
            $row=[Windows.Controls.Grid]::new();$row.Margin='0,0,0,8';$row.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$auto=[Windows.Controls.ColumnDefinition]::new();$auto.Width='Auto';$row.ColumnDefinitions.Add($auto)
            $check=[Windows.Controls.CheckBox]::new();$check.Content=$server.name;$check.Foreground=[Windows.Media.Brushes]::White;$check.IsChecked=[bool]$server.enabled;$check.Tag=$server;$check.VerticalAlignment='Center';[void]$row.Children.Add($check)
            $remove=[Windows.Controls.Button]::new();$remove.Content='Remove';$remove.Tag=[string]$server.name;$remove.Padding='10,5';$remove.Add_Click({param($s,$e)$settings.servers=@($settings.servers | Where-Object {$_.name -ne [string]$s.Tag}); & $refresh});[Windows.Controls.Grid]::SetColumn($remove,1);[void]$row.Children.Add($remove);[void]$panel.Children.Add($row)
        }
    }
    & $refresh
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
        $settings.useWithNInfer=[bool]$local.IsChecked
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
    if($SmokeTest){$dialog.Add_ContentRendered({Write-Host 'MCP manager rendered';$dialog.Close()})}
    [void]$dialog.ShowDialog()
}
