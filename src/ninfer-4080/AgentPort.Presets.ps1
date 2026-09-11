function Find-AgentPortStandardPreset {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($script:Config.harness_root){
        $root=[string]$script:Config.harness_root
        $candidates.Add((Join-Path $root 'packages\preset\agent-presets\presets\standard\agent.cordis.yml'))
        $candidates.Add((Join-Path $root 'node_modules\@deepseek-ai\dsh-agent-presets\presets\standard\agent.cordis.yml'))
    }
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
    $text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
    $persona=@'
    text: |-
      You are Zura Fast, a practical coding agent powered by the {{model}} model. Your working directory is {{cwd}}.

      Act quickly. Inspect only enough to identify the relevant path, make the smallest safe change, and run the narrowest useful check. Do not repeat analysis, create long plans, use workflows or delegate routine work. When uncertainty is minor, choose the conventional reversible option and proceed. Ask only when a missing choice materially changes the result or an action is unsafe. Stop as soon as the requested outcome is complete and summarise it briefly.

      Use connected MCP tools directly for ComfyUI and Blender. A matching skill is not required. Do not search for or install skills just because the user asks to use a connected app. Inspect available models, nodes or the current scene with a targeted tool call, perform the requested work, and verify the result. Continue through ordinary tool results without asking the user to say continue. If a tool fails, try one focused correction, then explain the concrete blocker. Do not claim an image was generated or a scene changed unless the tool result confirms it.
'@
    $pattern='(?ms)(- id: persona\s*\r?\n\s+name:.*?\r?\n\s+config:\s*\r?\n)\s+text:\s*[>|]-?.*?(?=\r?\n\r?\n- id: agent-instructions)'
    $updated=[regex]::Replace($text,$pattern,{param($match)$match.Groups[1].Value+$persona},1)
    if($updated -eq $text -or $updated -notmatch 'You are Zura Fast'){throw 'The installed Harness preset format was not recognised. Update Harness, then try again.'}
    $updated=[regex]::Replace($updated,'(?m)^(\s*maxRounds:\s*)\d+','${1}8')
    [IO.File]::WriteAllText($destination,$updated,[Text.UTF8Encoding]::new($false))
    $metadata=@'
name: Zura Fast
description: Fast, action-first coding with short planning and bounded retries.
order: 1
'@
    [IO.File]::WriteAllText((Join-Path $presetRoot 'preset.yml'),$metadata,[Text.UTF8Encoding]::new($false))
    $settings=Join-Path $env:USERPROFILE '.dsh\settings.yaml'
    if(Test-Path $settings){
        $settingsText=[IO.File]::ReadAllText($settings,[Text.Encoding]::UTF8)
        Copy-Item -LiteralPath $settings -Destination ($settings+'.before-zura-low-thinking') -Force
        if($settingsText -match '(?m)^agent-presets:\s*$'){
            $defaultPattern='(?m)(^agent-presets:\s*\r?\n\s+default:\s*)[^\r\n]+'
            $next=[regex]::Replace($settingsText,$defaultPattern,'${1}zura-low-thinking',1)
            if($next -eq $settingsText -and $settingsText -notmatch '(?m)^\s+default:\s*'){$next=$settingsText.TrimEnd()+"`r`n  default: zura-low-thinking`r`n"}
            $settingsText=$next
        }
        else {$settingsText=$settingsText.TrimEnd()+"`r`nagent-presets:`r`n  default: zura-low-thinking`r`n"}
        [IO.File]::WriteAllText($settings,$settingsText,[Text.UTF8Encoding]::new($false))
    }
    return $destination
}
