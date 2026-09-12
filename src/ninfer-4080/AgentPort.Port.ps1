function Select-AgentPortBackendPort {
    param([int]$Preferred=5100)
    foreach($candidate in @($Preferred)+(15100..15150)){
        $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$candidate)
        try {$listener.Start();return $candidate}
        catch {
            $errorCause=$_.Exception
            while($errorCause.InnerException){$errorCause=$errorCause.InnerException}
            # Preserve a live preferred endpoint so the ownership-aware stop
            # controls can inspect it. Windows reserved ports throw AccessDenied.
            if($candidate -eq $Preferred -and $errorCause.SocketErrorCode -eq [Net.Sockets.SocketError]::AddressAlreadyInUse){return $candidate}
        }
        finally {$listener.Stop()}
    }
    throw 'Windows has no available local backend port. Restart Windows and try again.'
}
$script:BackendPort=5100
if($env:AGENTPORT_BACKEND_PORT -match '^\d+$'){$script:BackendPort=[int]$env:AGENTPORT_BACKEND_PORT}
