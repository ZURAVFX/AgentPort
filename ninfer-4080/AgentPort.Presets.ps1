function Find-AgentPortStandardPreset {
    $candidates=New-Object System.Collections.Generic.List[string]
    if($script:Config.harness_root -and $script:Config.harness_runtime -ne 'npx-latest'){
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
    prefix: |-
      You are Zura Fast, a practical coding agent powered by the {{model}} model. Your working directory is {{cwd}}.

      Act quickly. Inspect only enough to identify the relevant path, make the smallest safe change, and run the narrowest useful check. Do not repeat analysis, create long plans, use workflows or delegate routine work. When uncertainty is minor, choose the conventional reversible option and proceed. Ask only when a missing choice materially changes the result or an action is unsafe. Stop as soon as the requested outcome is complete and summarise it briefly.

      Use connected MCP tools directly for ComfyUI and Blender. A matching skill is not required. Do not search for or install skills just because the user asks to use a connected app. Inspect available models, nodes or the current scene with a targeted tool call, perform the requested work, and verify the result. Continue through ordinary tool results without asking the user to say continue. If a tool fails, try one focused correction, then explain the concrete blocker. Do not claim an image was generated or a scene changed unless the tool result confirms it.
'@
    $pattern='(?ms)(^- id: persona\r?\n.*?  config:\r?\n).*?(?=^- id: |\z)'
    $updated=[regex]::Replace($text,$pattern,{param($match)$match.Groups[1].Value+$persona+"`n`n"},1)
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
    [void](Set-AgentPortPresetDefault -Path $settings -Preset 'zura-low-thinking' -BackupSuffix '.before-zura-low-thinking')
    return $destination
}

function Ensure-AgentPortSkillIsolation {
    # AgentPort-owned presets must not inherit Harness' global/project skill
    # roots. Those roots can include skills installed for Codex or other
    # agents (for example Impeccable). Only the explicit Harness folder is
    # mounted for these presets. User-created presets are never changed.
    $skills=([string]$script:Config.harness_skills_root).Replace('\','/').Replace("'","''")
    foreach($name in @('zura-low-thinking','agentport-fast')){
        $file=Join-Path $env:USERPROFILE ('.dsh\.agent-presets\'+$name+'\agent.cordis.yml')
        if(-not(Test-Path -LiteralPath $file)){continue}
        $text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)
        $pattern='(?ms)(^- id: skill-filesystem\r?\n.*?)(?=^- id: |\z)'
        $match=[regex]::Match($text,$pattern)
        if(-not $match.Success){continue}
        $block=$match.Groups[1].Value
        if($block -match '(?m)^\s*includeDefaultRoots:\s*false\s*$' -and $block -match '(?m)^\s*customSkillDirs:'){continue}
        $replacement='$1'+[Environment]::NewLine+'  config:'+([Environment]::NewLine)+'    includeDefaultRoots: false'+([Environment]::NewLine)+'    customSkillDirs:'+([Environment]::NewLine)+'      - '''+$skills+''''+([Environment]::NewLine)
        $updatedBlock=[regex]::Replace($block,'(?m)^(\s*name:\s*[''\"]?@deepseek-ai/dsh-skill-filesystem[''\"]?\s*)$',$replacement,1)
        if($updatedBlock -eq $block){continue}
        $backup=$file+'.before-skill-isolation'
        if(-not(Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $file -Destination $backup -Force}
        $text=$text.Substring(0,$match.Index)+$updatedBlock+$text.Substring($match.Index+$match.Length)
        [IO.File]::WriteAllText($file,$text,[Text.UTF8Encoding]::new($false))
        Set-Log ('Restricted '+$name+' to the explicit Harness skills folder.') 'ok'
    }
}

function Repair-AgentPortPresetCompatibility {
    # Only migrate AgentPort-created presets, never the user's other presets.
    foreach($name in @('zura-low-thinking','agentport-fast')){
        $file=Join-Path $env:USERPROFILE ('.dsh\.agent-presets\'+$name+'\agent.cordis.yml')
        if(-not(Test-Path -LiteralPath $file)){continue}
        $runtime=Get-AgentPortSettingsRuntime
        $helper=Join-Path $script:AgentPortRoot 'ninfer-4080\AgentPort.PresetCompatibility.js'
        $result=& $runtime.NodePath $helper $file $runtime.YamlRoot 2>&1
        if($LASTEXITCODE -ne 0){throw ('Could not update the '+$name+' preset safely. The original has been preserved.')}
        if([string]$result -eq 'changed'){Set-Log ('Updated '+$name+' for the installed Harness. Original preset backed up.') 'ok'}
    }
}
