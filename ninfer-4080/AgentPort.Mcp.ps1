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
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="MCP connections" Width="660" Height="630" WindowStartupLocation="CenterOwner" Background="#10141B" Foreground="White">
<StackPanel Margin="20">
<TextBlock Text="Add tools to DeepSeek Harness" FontSize="22" Margin="0,0,0,12"/>
<TextBlock Text="Paste the server's mcpServers JSON below, or create a filesystem template. Local commands run on your PC. Enable only servers you trust." TextWrapping="Wrap" Margin="0,0,0,10"/>
<Button x:Name="Template" Content="Add a folder / filesystem server" HorizontalAlignment="Left" Padding="10,6"/>
<TextBox x:Name="Input" Height="150" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" Margin="0,10,0,8"/>
<Button x:Name="Import" Content="Import configuration" HorizontalAlignment="Left" Padding="10,6"/>
<TextBlock Text="Enabled servers" Margin="0,12,0,5"/>
<ScrollViewer Height="100"><StackPanel x:Name="Servers"/></ScrollViewer>
<CheckBox x:Name="Local" Content="Also enable these and existing MCP servers for NInfer" Foreground="White" Margin="0,10,0,4"/>
<TextBlock Text="MCP tools consume context and can slow prompt processing. Saved connections take effect when Harness restarts. Tokens in pasted JSON are stored in your local configuration." TextWrapping="Wrap" Foreground="#BBBBBB" Margin="0,4,0,8"/>
<StackPanel Orientation="Horizontal"><Button x:Name="Save" Content="Save" Padding="16,8"/><Button x:Name="Restart" Content="Save and restart Harness" Margin="8,0,0,0" Padding="16,8"/></StackPanel>
<TextBlock x:Name="Status" TextWrapping="Wrap" Margin="0,8,0,0"/>
</StackPanel></Window>
'@
    $dialog=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout));$dialog.Owner=$Window
    $settings=Get-AgentPortMcpSettings
    $inputBox=$dialog.FindName('Input');$panel=$dialog.FindName('Servers');$status=$dialog.FindName('Status');$local=$dialog.FindName('Local')
    $local.IsChecked=[bool]$settings.useWithNInfer
    $refresh={
        $panel.Children.Clear()
        foreach($server in @($settings.servers)){$check=[Windows.Controls.CheckBox]::new();$check.Content=$server.name;$check.Foreground=[Windows.Media.Brushes]::White;$check.IsChecked=[bool]$server.enabled;$check.Tag=$server;[void]$panel.Children.Add($check)}
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
        & $refresh;$status.Text='Imported. Review enabled servers, then save.'
    } catch {$status.Text=$_.Exception.Message}})
    $save={
        foreach($check in $panel.Children){$check.Tag.enabled=[bool]$check.IsChecked}
        $settings.useWithNInfer=[bool]$local.IsChecked
        Ensure-ConfigDir
        $path=Join-Path $script:ConfigDir 'agentport-mcp.json'
        if(Test-Path $path){Copy-Item $path ($path+'.bak') -Force}
        [IO.File]::WriteAllText($path,($settings|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
        $status.Text='Saved. Start or restart Harness to connect the enabled servers.'
    }
    $dialog.FindName('Save').Add_Click({try {& $save}catch{$status.Text=$_.Exception.Message}})
    $dialog.FindName('Restart').Add_Click({try {
        & $save
        if(-not $script:PendingModel){throw 'Choose a model and use Apply & Start first.'}
        Kill-HarnessOnly
        Start-Sleep -Milliseconds 700
        if(Test-Port 3080){throw 'An externally started Harness is using port 3080. Close it before restarting.'}
        if($script:NInferState){$script:NInferHarnessPatch=New-NInferHarnessPatch (Join-Path $script:NInferState.LogDirectory 'coding.patch.yml')}
        Start-Harness;$status.Text='Harness is restarting. Connection failures appear in the Harness log.'
    } catch {$status.Text=$_.Exception.Message}})
    if($SmokeTest){$dialog.Add_ContentRendered({Write-Host 'MCP manager rendered';$dialog.Close()})}
    [void]$dialog.ShowDialog()
}
