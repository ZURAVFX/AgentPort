function Find-AgentPortStandardPreset {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($script:Config.harness_root){$candidates.Add((Join-Path ([string]$script:Config.harness_root) 'node_modules\@deepseek-ai\dsh-agent-presets\presets\standard\agent.cordis.yml'))}
    $cache=Join-Path $env:LOCALAPPDATA 'AgentPort\npm-cache'
    if(Test-Path $cache){
        Get-ChildItem -LiteralPath $cache -Filter agent.cordis.yml -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {$_.FullName -like '*dsh-agent-presets*presets\standard\agent.cordis.yml'} |
            Sort-Object LastWriteTime -Descending | ForEach-Object {$candidates.Add($_.FullName)}
    }
    foreach($candidate in @($candidates | Select-Object -Unique)){if(Test-Path -LiteralPath $candidate){return $candidate}}
    throw 'DeepSeek Harness must be installed before adding this preset. Start Harness once, then try again.'
}

function Install-AgentPortLowThinkingPreset {
    $source=Find-AgentPortStandardPreset
    $presetRoot=Join-Path $env:USERPROFILE '.dsh\.agent-presets\zura-low-thinking'
    $destination=Join-Path $presetRoot 'agent.cordis.yml'
    New-Item -ItemType Directory -Force -Path $presetRoot | Out-Null
    if(Test-Path $destination){Copy-Item -LiteralPath $destination -Destination ($destination+'.backup') -Force}
    $text=Get-Content -LiteralPath $source -Raw
    $persona=@'
    text: |-
      You are Zura Low Thinking, a practical coding agent powered by the {{model}} model. Your working directory is {{cwd}}.

      Default to action. For implementation requests, inspect only enough code to identify the relevant path, then make the smallest correct change and verify it. Do not keep analysing once you have a safe, testable approach. Prefer a working implementation over an exhaustive discussion of alternatives.

      Keep internal reasoning focused and bounded. For routine work, use only a few targeted discovery steps before editing. If uncertainty is minor, choose the conventional reversible approach and proceed. Ask only when a missing decision would materially change the result or an action is unsafe or irreversible.

      Do not create elaborate plans, long todo lists, workflows, or subagents for straightforward tasks. Avoid rereading the same files, reconsidering settled decisions, or polishing beyond the requested outcome. Explicit plan mode remains thorough and decision-complete.

      After editing, run the narrowest relevant check. If it fails, diagnose and fix it. Finish with a concise summary of what changed, what was verified, and any real remaining limitation.
'@
    $pattern='(?ms)(- id: persona\s*\r?\n\s+name:.*?\r?\n\s+config:\s*\r?\n)\s+text: \|-.*?(?=\r?\n\r?\n- id: agent-instructions)'
    $text=[regex]::Replace($text,$pattern,{param($match)$match.Groups[1].Value+$persona})
    $text=[regex]::Replace($text,'(?m)^(\s*maxRounds:\s*)\d+','$1'+'8')
    [IO.File]::WriteAllText($destination,$text,[Text.UTF8Encoding]::new($false))
    $settings=Join-Path $env:USERPROFILE '.dsh\settings.yaml'
    if(Test-Path $settings){
        $settingsText=Get-Content -LiteralPath $settings -Raw
        Copy-Item -LiteralPath $settings -Destination ($settings+'.before-zura-low-thinking') -Force
        if($settingsText -match '(?m)^agent-presets:\s*$'){$settingsText=[regex]::Replace($settingsText,'(?m)(^agent-presets:\s*\r?\n\s+default:\s*)[^\r\n]+','${1}zura-low-thinking')}
        else {$settingsText=$settingsText.TrimEnd()+"`r`nagent-presets:`r`n  default: zura-low-thinking`r`n"}
        [IO.File]::WriteAllText($settings,$settingsText,[Text.UTF8Encoding]::new($false))
    }
    return $destination
}
