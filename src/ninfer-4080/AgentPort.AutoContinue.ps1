function Get-AgentPortAutoContinuePath {
    Join-Path $env:LOCALAPPDATA 'AgentPort\auto-continue.json'
}

function Save-AgentPortAutoContinueOptions([bool]$Enabled,[int]$Limit=10) {
    if($Limit -lt 1 -or $Limit -gt 50){throw 'Choose between 1 and 50 automatic continuations.'}
    $path=Get-AgentPortAutoContinuePath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $json=@{enabled=$Enabled;maxContinuations=$Limit} | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,($path+'.previous'))}else{[IO.File]::Move($temp,$path)}
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Get-AgentPortAutoContinueOptions {
    try {
        $value=Get-Content -LiteralPath (Get-AgentPortAutoContinuePath) -Raw -ErrorAction Stop | ConvertFrom-Json
        if($value.PSObject.Properties.Name -notcontains 'maxContinuations'){$value | Add-Member -NotePropertyName maxContinuations -NotePropertyValue 10}
        $limit=$value.maxContinuations
        $numeric=($limit -is [int] -or $limit -is [long] -or $limit -is [double])
        if($value.enabled -isnot [bool] -or -not $numeric -or $limit -ne [math]::Floor([double]$limit) -or $limit -lt 1 -or $limit -gt 50){throw 'Invalid options'}
        return $value
    } catch {return [pscustomobject]@{enabled=$false;maxContinuations=10}}
}
