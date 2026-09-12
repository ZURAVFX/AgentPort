$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'AgentPort.Port.ps1')
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
try {
    $listener.Start()
    $occupied=$listener.LocalEndpoint.Port
    if((Select-AgentPortBackendPort $occupied) -ne $occupied){throw 'Existing endpoint was lost: stop controls must retain it.'}
} finally {$listener.Stop()}
$selected=Select-AgentPortBackendPort 5100
$probe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$selected)
try {$probe.Start()} finally {$probe.Stop()}
'Port selection tests passed.'
