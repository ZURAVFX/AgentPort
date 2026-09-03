Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

try {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AgentPortShellIdentity {
    [DllImport("shell32.dll", SetLastError=true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appID);
}
"@
[void][AgentPortShellIdentity]::SetCurrentProcessExplicitAppUserModelID('ZURAVFX.AgentPort')
} catch {}

$ErrorActionPreference = 'Stop'
$script:AppVersion = '1.6.2'
$script:ConfigDir = Join-Path $env:USERPROFILE '.dsh'
$script:ConfigFile = Join-Path $script:ConfigDir 'launcher_config.json'
$script:SettingsPath = Join-Path $script:ConfigDir 'settings.yaml'
$script:ProfilesFile = Join-Path $script:ConfigDir 'agentport_profiles.json'
$script:Models = @()
$script:RepoFiles = @()
$script:LaunchState = 'idle'
$script:LaunchDeadline = $null
$script:PendingModel = ''
$script:PendingContext = 49152
$script:Download = $null
$script:StatusBusy = $false
$script:BootstrapProcess = $null
$script:BootstrapLog = ''
$script:TextGenProcess = $null
$script:LaunchPhase = 0
$script:InstallOnlyMode = $false
$script:LastModelScanRoots = @()
$script:AppDataDir = Join-Path $env:LOCALAPPDATA 'AgentPort'
$script:PublicDataDir = Join-Path $env:PUBLIC 'AgentPort'
$script:PortableNodeVersion = '22.23.1'
$script:PortableNodeDir = Join-Path $script:AppDataDir ('node-v'+$script:PortableNodeVersion+'-win-x64')
$script:PortableNpx = Join-Path $script:PortableNodeDir 'npx.cmd'
$script:NpmCacheDir = Join-Path $script:AppDataDir 'npm-cache'

$script:Defaults = [ordered]@{
    textgen_root = (Join-Path $script:PublicDataDir 'textgen')
    harness_root = (Join-Path $script:AppDataDir 'harness-workspace')
    models_root = (Join-Path $script:PublicDataDir 'models')
    harness_skills_root = (Join-Path $env:USERPROFILE '.dsh\harness_skills')
    last_model = ''
    last_context = '48k (49,152 tokens)'
    cache_type = 'q4_0'
    offload_mode = 'Auto Fit (Recommended)'
    draft_mtp = $true
    speculative_mode = 'Medium'
    max_tokens = 2048
    active_model = ''
    active_context_tokens = 0
    active_offload_mode = ''
}

$script:ContextPresets = [ordered]@{
    '32k (32,768 tokens)' = 32768
    '48k (49,152 tokens)' = 49152
    '64k (65,536 tokens)' = 65536
    '100k (102,400 tokens)' = 102400
    '110k (110,592 tokens)' = 110592
    '128k (131,072 tokens)' = 131072
}

$script:OffloadModes = [ordered]@{
    'Auto Fit (Recommended)' = @{ gpu_layers = -1; fit_target = 768; note = 'Best default. Fills the GPU while leaving a little headroom.' }
    'Auto Fit (Safe Headroom)' = @{ gpu_layers = -1; fit_target = 2048; note = 'Leaves about 2 GB VRAM free for Windows and creative apps.' }
    'Maximum GPU (Aggressive)' = @{ gpu_layers = 999; fit_target = $null; note = 'Pushes as much as possible to the GPU. Fast, but less forgiving.' }
    'CPU / RAM Only' = @{ gpu_layers = 0; fit_target = $null; note = 'Keeps model layers off the GPU. Slowest, but frees VRAM.' }
}

function Ensure-ConfigDir {
    if(-not (Test-Path -LiteralPath $script:ConfigDir)){ New-Item -ItemType Directory -Force -Path $script:ConfigDir | Out-Null }
}

function Load-Config {
    Ensure-ConfigDir
    $cfg = [ordered]@{}
    foreach($k in $script:Defaults.Keys){ $cfg[$k] = $script:Defaults[$k] }
    if(Test-Path -LiteralPath $script:ConfigFile){
        try {
            $raw = Get-Content -LiteralPath $script:ConfigFile -Raw | ConvertFrom-Json
            foreach($p in $raw.PSObject.Properties){ $cfg[$p.Name] = $p.Value }
        } catch {}
    }
    return $cfg
}

function Save-Config {
    Ensure-ConfigDir
    $script:Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
}

$script:Config = Load-Config

$script:AppIconBase64 = @'
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
RK5CYII=                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              
'@
$script:BrandLogoBase64 = @'
iVBORw0KGgoAAAANSUhEUgAACAAAAAZkCAYAAABx/eUhAAAABmJLR0QA/wD/AP+gvaeTAAAgAElEQVR4nOzdeZTlZ13v+++za87UmSAhkBCGQAiQAGEeRCGC
BqJ4rhEcAkdEHDgS9ShxnXvPheu5HoJ6MFFEUODI4BWCSpgECUMYAojEMCnBBMEBUJfHpLur9vP8Kun9vX90oeGYkHR3VT1Vu16vtbKatRK63n90UrV/v8/v
+UUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKyz0jsAAAAAAAAAdpLMPGr37pjp3bFTHX10uaF3A2yU2d4BAAAA
AAAAsJO0NnxsYSHO6N2xQ90UEfO9I2CjjHoHAAAAAAAAAACHzgAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAA
YAoYAAAAAAAAAADAFDAAAAAAAAAAAIApYAAAAAAAAAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABg
ChgAAAAAAAAAAMAUMAAAAAAAAAAAgClgAAAAAAAAAAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAK
GAAAAAAAAAAAwBQwAAAAAAAAAACAKWAAAAAAAAAAAABTwAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoY
AAAAAAAAAADAFDAAAAAAAAAAAIApYAAAAAAAAAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgA
AAAAAAAAAMAUMAAAAAAAAAAAgClgAAAAAAAAAAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAA
AAAAAAAAwBQwAAAAAAAAAACAKWAAAAAAAAAAAABTwAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoYAAAA
AAAAAADAFDAAAAAAAAAAAIApYAAAAAAAAAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgAAAAA
AAAAAMAUMAAAAAAAAAAAgClgAAAAAAAAAAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAAAAAA
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
5cyqnJbk1CQn9u69taryudbyT0m7Nqlrk3Zta/XPk0k+mbRPtDb5eJJPzM7OfqK1drB3LwAAAABAYgAAAMBRVlVbrr/++lO3bt162mQyOXUwGJxa1U5trU6a
TNrJrWXYWm2fTHJCa9naWk5NsrUqJyRte2s1/PefLzuSbLuR33Jfaznwb37/Strnjnz3UGu5viqfr8r+wSA3VLXrqmr/YJB9k0m7bjCo/VW1dzAYXHvo0KFr
d+zYcW1rbXz0/2QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAmHKt
dwAAAAAAwHo12ll3XBvn9N4d3DSfPiHvv+KKdqh3BwBAL1t6BwAAAAAArFfjSX4sg/xQ7w5umjMP5nZJPtW7AwCgl0HvAAAAAAAAAADg1jMAAAAAAAAAAIAp
YAAAAAAAAAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgAAAAAAAAAAMAUMAAAAAAAAAAAgClg
AAAAAAAAAAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAAAAAAAAAAwBQwAAAAAAAAAACAKWAA
AAAAAAAAAABTwAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoYAAAAAAAAAADAFDAAAAAAAAAAAIApYAAA
AAAAAAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgAAAAAAAAAAMAUMAAAAAAAAAAAgClgAAAA
AAAAAAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAAAAAAAAAAwBQwAAAAAAAAAACAKWAAAAAA
AAAAAABTwAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoYAAAAAAAAAADAFDAAAAAAAAAAAIApYAAAAAAA
AAAAAFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgAAAAAAAAAAMAUMAAAAAAAAAAAgClgAAAAAAAA
AAAAU8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAAAAAAAAAAwBQwAAAAAAAAAACAKWAAAAAAAAAA
AABTwAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoYAAAAAAAAAADAFDAAAAAAAAAAAIApYAAAAAAAAAAA
AFPAAAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCBgAAAAAAAAAAMAUMAAAAAAAAAABgChgAAAAAAAAAAMAUMAAAAAAAAAAAgClgAAAAAAAAAAAA
U8AAAAAAAAAAAACmgAEAAAAAAAAAAEwBAwAAAAAAAAAAmAIGAAAAAAAAAAAwBQwAAAAAAAAAAGAKGAAAAAAAAAAAwBQwAAAAAAAAAACAKWAAAAAAAAAAAABT
wAAAAAAAAAAAAKaAAQAAAAAAAAAATAEDAAAAAAAAAACYAgYAAAAAAAAAADAFDAAAAAAAAAAAYAoYAAAAAAAAAADAFDAAAAAAAAAAAIApYAAAAAAAAAAAAFPA
AAAAAAAAAAAApoABAAAAAAAAAABMAQMAAAAAAAAAAJgCW3oHAAAAAMBmNtpV2w9+ISdum8mJa5Oc/C//Y5DtNcgwSWot1w8qh5JkXLlh2HIwSQ5Wbpgc+fbl
r217O+QDAADriAEAwH9w8XzN7dieM9s4X10tp7fkpKqcnOSktJxcycktOSXJSakj/462zKZl7l8+SeWklhyqlv1Hvv+FVMZJ0lr2Jkm1HKrK9YOWfZPk2la5
tlr+eWYt/zzekmtbcu3WQa4dXdlWj/MfAQAbRrXRfE7NMKetVU6t5NQ2yGn1xW+3nFaVE5OkJcOWbD/8y7Ktkh05/D+2puWEIz++pZITW/K5tNSRH7sulcmR
3/DzrWUtSSbtXx/bBpXPVctnW8vemuSzg2TvuGXvti357P4bsvf5V7XrjuMfCgCsC6NRDfKhnLnWcpckd5lU7pyW0wfJ7Sq5bZLT03J6KieP92VmMJMjD6z/
4RMdeRRuLal2+NszOfJzj/z0L/6S5cVKks8n+Xwq1yX5fNrh/1byuUHlc3X48fy6qnyqtXx6vJZ/mozzSY/XAAAwHVrvAIDjq9poIbcft9wtLXdtyd2qcock
t8/hF2DOTP7Nuy3WhxuS/HOSj6fykbR8tFU+WoN8dMtaPvqPJ+TjV1zRDvWOBODoGV1YswcmuePWtdxhLTkryZ3SDj9eteT0Sk5ryak5/LERTJJ8NsneJJ9N
yz9V5WOt5R/aJB9Py9/PbMnH/3FbPuExDYCNZvfuGp5yXc7JWu6VlnsnuVeSe1dy5yTb+tbdLAfS8pkkn0zymVT+qVU+UcnHBsmHB5WP5B/zsdG72vgrfaJp
s7xYL07yQ707uGm2bMntRle2T/XuAADoxQAAmErz8zVzj2Hu1pL7JblfJeckuduRj9m+dUfdWpJ/SPLRJNdU5S/aIO9fa/nz572yXds3DYAvZdeu2nqbG/I1
M8k51XLnweEx2p3q8CH/WUnO6JzYyyTJp5J8rCUfr8OPb39fLR9ug3xwy13ykdGoTb7C5wCAY2Z+vma+ZmvuOzPIAyfJN7TkgUnum2Rr77bjZJzk40k+UsmH
k3xkMsivPe+V7W87dx1TBgAbiwEAALDZuQUAsOF98QWYwUweVpX7Hzn0v0+Sueodd3zMJLnTkY9vaS1JJTOVLC/WJ5J8IMmft8r7k3zg0zvy195dCXB87NpV
W8+8Pnc4NJN7t8o5qdw7g5yTfbl32uFBWsu/Xs6XDHL4ajxnVvKQL/5gqyRryfiaHFxZrGuS/GUlH6yWvxys5cOfu03+4kUvagd6RQMwvebna+aeW3P/GuTh
LXlYJecmObWyad9VsyU5fEuDlnxbksxM8skkUz0AAACAjcQAANhwRhfWKQcP5RsHLd9YyUNb8uAkJ6Q27QswN+b2Rz4e/cXDpTP25eDyYv1JkquTvGdtkKtd
KQDg1tuzs27fKg9ulQfki5f+3Zezx4NsaV9cpB0ZaXGLbTtyVZ9zksPDgBokJ+/NweXF+uu0/FUqf5mW920Z549Hr2v/3LkXgA1otFRnrFUeneSxlTyqklMS
D+EAAMDG4KxsHRkt1EmrlZneHXx5s4dyw+iqdrB3x2aza1dtPf36fOOg5VE1yH/J4YMVf1eOnmrJX02S96TlPS15z7Nf1T7SOwpgPXvaUu0Ytnxdm+QBqTyg
Wh7WkrN7d/GffDIt70vlPTXI1fv2530/c1Xb3zsKNqqnLdWOLWsb6n7mm8pkNuOf+OX2hd4dG9VlS3WfQeXxSR6Xw1eV85rZTVTJ7rVJXtO741iamclPtsqT
endwk91zPMlnekdMswOHsup5NQCsX76YWUdWluqvqnLP3h18eZUsPufVbaq/qF0vRgt11niQx7XKt1fyrUlO6N20yXwilXdW8ta1ym9f/tq2t3cQQE+j8+vs
tUEefuSw/wFJviFxCLYBjVvyt5PkPYPk6szkfc96RT545CYDwFewZ6Fe3lou7N3Bl/WuZ7+6fWvviI1kZaHuW4M8oSXf7/UYgJvlZ5796vbU3hEAwJfmFgDA
ujG6sO48HudxSebHyUNTXo3v6PZpWWrJ0paWteWl+rNU3tImefOzXps/dVACTLvR+XX22kzOTeXcannkuHJaEvPZjW9LJee05JxKdmUtWV7MZ1rq3Wl5x+RQ
3v6c17eP944E4Nj5sfPr1K0zma/KzkoelnJpfwAAYLoYAABdLS/VXVJZTDI/Hue+vXv4kmaO3HbhATXIM5cX8/eVemtreesNq/k9l3wDpsFovk4Yz+UhmeTc
tJw7rjzgX04DnApMuzMqmU9lvm1J9izWh5O8Iy3vGK/mt59/VbuudyAAt1a15Z15ZNbyQ2l5bJWr+AAAANPLAAA47kYLddJay/dUZSmVR8b7KTeaO7Xkh1P5
4R3D7F9ZrLdMWl71T3P5zSuuaId6xwHcFKP52jYe5qFpOTfJo8aVB2SSmSQO/De5lpydZFcqu7YOc3B5sf4glXdU5Xe23j1/Mhq1Se9GAG6apz+pThweynlV
2Z1J7uMrTwAAYDMwAACOm+XFekSSXePke5LMefFlKsxVMt8q82fsy6dXFupXMshrn/Wq9ke9wwD+o9GFNXtoLY9K5bHj5HuTnO6wn69gW5JHpOURreXZ42ty
7fJCva0GucrwDWD92vPEusNga55aB/NfKzmhdw8AAMDxZAAAHFOj+TphbTbnV+VHknxt7x6OqdtWy0WpXLS8WB9L8rq1tVz5vNe1v+4dBmxeF8/X3PbZnNsm
mR+P87iWnNS7iQ3tNmlZapWlM/Zl7/JCvaUGuerzp+S3X/SidqB3HMBmt3xB3bWNc1G17KrKbO8eAACAHgwAgGNitFh3G7dcNK5ckHLYsgndMcklMzO5ZHmx
3lstL/78KflVhyPA8TDaVdsP7c8j2yTzafneVE5w1RmOgVO/OAY4eW/2LS/VO1vlqpkD+fXRVe363nEAm8ml59U9Z2by41nL46tl0LsHAACgJwMA4Ki6bGd9
7WAtTxsn56X8G0OS5CGt8pCT9+ZnVxbqlTXIC579qvaR3lHAdBldWLNra/meqiyN9+Xclmxz6M9xtD2Vx1by2PEwL15ZrLdV5ZV/czBvv+qqttY7DmBa7Tm/
7pRBLmvJk+I1LgAAgCS+OAKOkj076+GtckkmeUyaIxe+pFOO3CLgR5cX6p01yBV/u5pfdzAC3BorF9S9ay1L43GenOSrevdAkh2VzKdl/h7DfHJloa5K8rJn
vaZ9oHcYwLS4dGfdZjDJqCU/mGRr7x4AAID1xAAAuFX2LNZDW/K8TPLNvVvYMAZpObdVzr37MNcsL9QvbEl+cfSa9vneYcDGcMl8nbxtNk+oys5ay8N698CN
uF21XJTkouWlel9LrphZzWvdIgDglhk9oras3SFPqkmeneT03j0AAADrkQEAcItculDnbGkZVfL4xDv+uWVacre0/OQ4eebKQr18bZLnPvd17dO9u4D1ZzSq
waEP56GZZKkli1XZ3rsJbpbKAyp56XiYF6ws1ltqkCue/cr8btKqdxrARvCMxXrUWsvPVuWevVsAAADWMwMA4GYZXVh3Hq/lOak8sZJB7x6mxonVctFgJk9a
XqyXbNmSnx5d2T7VOwrobzRfp41n84Pja/KDLblT7x44CuYqmc8k8ytL+etJ6iVbV/PLrgoA8KWN5uu0Q8M8b5L8vynjcwAAgK/EAAC4SUa7avt4X54+Hufp
SeZ69zC1TkjyP8fjPGV5oX4lW/Ljz35F+7veUcDxt3xB3bWNc9G45cmp7OjdA8dCVe7ZkheOh3nWykJdOTOTnxq9sn2sdxfA+lBtZTFPHrc8v1VO610DAACw
URgAAF9BtZWlPGG8Pz+R5A69a9g0tqVlKWt5wvJivWrLJM8dvbZ9uHcUcOzt2VkPH0xyUa3l+6plpncPHCcnVctF40l+dHmp3tZanvusV7Y/7B0F0Mvowvrq
tXFeVslj4kYpAAAAN4sBAPBlXXpe3XNmJi+tyjf3bmHT2pbkyeNBllaW6sXjlmc/75Xt2t5RwNE1P18zd5/Nd7bKZZnkIV7nZxMbpPLYqjx2eane1yo/+9cH
8pqrrmprvcMAjpc9SzU/XssvJN71DwAAcEsYAAD/ya5dtfWMfXlqklGS2c45kCTbqvLfZyoXLi/W5Vu25IWjK9tq7yjg1rlkvk7eMpsfbJXdqZzVuwfWlcoD
KnnF3YdZWV6qF2yZy8tHV7R9vbMAjpUfO79O3TLIFak8vncLAADARjboHQCsLys76+vO2Jf3Jrk8Dv9Zf05Jcvl4LX+7slS7RqPyOAYb0NOWasfyYl2ydTYf
bpXnJw7/4ctpyd1S+bnxvnx0ebEuuXi+5no3ARxte5bqgTOD/Eni8B8AAODWcnACJElG87VtZaGeX5P8SZKv790DN6pyh6q8dHxN3rvn/HKLCtggdu+u4cpS
7ZqtXJPk8pRL+8LNcHqSy3cM87fLi/WU3btr2DsI4NartrxYT2mVq1tydu8aAACAaeAWAEBWLqh7j9fy6iT3790CN9M3tEHevbJYb5yM85TnvL59vHcQ8J+N
5mvb2mwurL15ZiVn9u6BDe6sJC84eW+eurJUz5n5eH559K427h0FcHONFuqkccurknx37xYAAIBp4goAsKlVW1mqXbWWP47DfzawSr63bclfLy/WJfPzNdO7
Bzhs167aurJYOw8N81dVeWkc/sPRdMeqvPTQ7fOhlaXa5fEP2EhGi3W3cfIHcfgPAABw1BkAwCZ16c66zZ7FvPXIgcz23j1wFGxPcvk9hnnvys76ut4xsJmN
RjXYs1AXnLEvf1PJK1zSF46d1nLnqrz0nsO8f3mhHp9U690EcGOWF+q/jJM/Tsu9e7cAAABMIwMA2IT2LNUDZyb5Py35jt4tcAw8sCb545WFeuHTn1Qn9o6B
zWZlob5hfE2ubi1XJrlL7x7YLCo5Jy1XLS/lvStL9eDePQBfyspC/XBa3pbk1N4tAAAA08oAADaZlaXa1SpXx6EM021LtVy07WD+anmpvq93DGwGoyfWmcsL
9cpq+aMkD+ndA5tW5UFV+YPlhXrlaKnO6J0DcFi15cUaVcvPJ3HLEgAAgGNoS+8A4Pi4eL7mdszmZVU5v3cLHEe3T+UNy4v1+vEkP3z5a9ve3kEwbUbztW08
zA+Nk2clcdUNWB8GaVkaV75rebEu33IgPzO6qh3sHQVsTkeeK/xykoXeLQAAAJuBKwDAJjB6Yp25YzbvisN/Nq8nbhnkg8uL9ejeITBN9izVdx0a5q+SvCAO
/2E9OiXJ5WvDfGB5qb6zdwyw+Yx21fZDw7wlDv8BAACOGwMAmHIrO+vrxlvyh6k8qHcLdPbVSd62slAvHM3Xtt4xsJFdurPuvrxYb22VN7Xk7N49wI2r5O6p
vHV5qd68fEHdtXcPsDk8bal2jPflzS15VO8WAACAzcQAAKbY8kI9vib5gyR37N0C60SrlovGw/zhpefVPXvHwEaze3cNlxfquTOT/EUS7yaGjaby2KzlL5cX
as/oEeV2cMAxc8l8nTw7ye8k+bbeLQAAAJuNAQBMqZXF+tG0/EqS2d4tsA59/cxM/nR5sZ6SVOsdAxvBylI9+JS9+dO0XJpka+8e4BYbpuXZ47PyvpXz6wG9
Y4DpM7qwTtk6m99Nyzf2bgEAANiMDABg6lRbXqzLK3lR/B2HGzOX5AXLi/mNS3+gTu8dA+vV6MKaXV6sy6tydSXn9O4BjpqvrUHeu7xYl+/eXcPeMcB0GO2q
7eNx3pSKgREAAEAnDgdhioweUVuWF3Nlkkt6t8AG8t0z47xvz1I9sHcIrDcrO+sb19byf3P4cWWmdw9w1G1JcsnJn8379pxfD+odA2xsF8/X3KH9eUuSb+rd
AgAAsJkZAMCUGM3XtvFZeV2Snb1bYMOp3KFV3rO8VE/unQLrwcXzNbe8WJfXJP+7Kvfs3QMcYy33boNcvbJQLxztqu29c4CNZzRf23YM8+ut8q29WwAAADY7
AwCYArt313BtW341yeN7t8AGNkzlZXsW66Wj+drWOwZ62bOzHn7CMH8W7/qHzWZLtVw03pf3ryzVt/SOATaSauNhfjHJo3uXAAAAYAAAG97TlmrHSZ/L26vl
cb1bYBq0ZNd4mHdcdl7dtncLHE+HbyNTozbJuyu5e+8eoJu7VuX3Vhbqhbt21dbeMcD6t7yQ58SV6AAAANYNAwDYwC6er7nZyptcZhGOum8azORP9yzUQ3qH
wPEw2ll3HJ+VdyV5Zjw/BJJWLRedsS/v2LOzbt87Bli/Vhbrv6bl0t4dAAAA/Csv8MIGtXt3DXcM8+tJvq13C0ypM1vLu5aX6sm9Q+BY2nN+PW5c+b9JHta7
BVh3vrlN8mfLC/XY3iHA+vOMpfr2Sl7SuwMAAIB/zwAANqBdu2rryXvzq3GPRTjWhqm8bGWhXphU6x0DR9Pu3TVcWagXtkHemMppvXuAdeur0vKmlYV64Wi+
tvWOAdaH5aW6y6TymiRbercAAADw7xkAwAYzGtXgjH15RZLv7t0Cm0W1XLS8mJe7FzLT4tKddfeT9+YPq+WiJMYtwFfSquWi8TBXL19Qd+0dA/Q1mq8TUnlT
ktv0bgEAAOA/MwCADWZ8TX4yyXm9O2ATuuD0fXn7aKFO6h0Ct8byQj1+ZpI/SvJ1vVuADeeBWcuf7lksz0Vh06o2HublSe7TuwQAAIAvzQAANpDlhdqT5OLe
HbBZteSR45b/vWdn3b53C9xco/natmexXpqWq5Kc0rsH2LBOaslr9yzWi0aPKJf+hk1meTFPT/L43h0AAAB8eQYAsEGsLNST0vKs3h1AvjaT/P7y+fU1vUPg
prp0Z93m0Gx+syW7ercA06ElPzo+K++89Afq9N4twPGx5/x6UJL/1bsDAACAG2cAABvAnvPrm6vlJXGfZlgXWnJ2ZvLelYV6WO8W+EouW6r7zEzyf1rlW3u3
AFPnm2YO5Q8vXahzeocAx9bowjqlDfL6JNt6twAAAHDjDABgnVterHu0QX4jXmiB9aVyWrX81jMW6pG9U+DLWV6sRw8q70lyl94twNS660zLe/cs1Xf1DgGO
nfGh/FI8nwAAANgQDABgHbt0Z92mkrckObV3C/Al7Zi0vMkIgPVoebGeksOPISf3bgGm3omt8sblxbqkdwhw9B25Hd339e4AAADgpjEAgHVqNKrBYC2vacnd
ercAN2r7pOXNyzvr3N4hkCSj+dq2vFi/nOQFSWZ69wCbxkySy5cX69WjC2u2dwxwdIwW6qxq+cneHQAAANx0BgCwTq19KD/eWr69dwdwk8xlkrdctliP6R3C
5jY6r75qPMxvJ/mB3i3AprUwHud3Lzuvbts7BLi1qh1KXhZXpAMAANhQDABgHbpssR5TLZf17gBuluEgeYMRAL2MFutu45n8cZJv6d0CbHoPbTP5g+UL6q69
Q4BbbmUxP2KUDgAAsPEYAMA6M9pZdxwkr4i/n7ARDQfJG5YX6rG9Q9hcVi6oe4+Tdye5S+8WgCRpydlZy9WXnV/3790C3HyjJ9aZlTy7dwcAAAA3nwNGWEd2
767heJI3JLlN7xbgFhum5deMADhe9pxfD6q1vDvJmb1bAP6D2w4G+b09O+vhvUOAm2dtS34uycm9OwAAALj5DABgHTlpb342yQN7dwC32jAtV60s1jf1DmG6
PWOhHtkG+d0YjgHr1yltkt9aXqrv7B0C3DSXLdR3VPK9vTsAAAC4ZQwAYJ3Ys1AXtGRX7w7gqJmt5E2XLdV9eocwnfYs1nmTlrcnOaF3C8BXsD2V/29lqS7s
HQLcuKct1Y5By0t6dwAAAHDLGQDAOjA6v85uLS/q3QEcdacMKr+15/y6U+8QpsvyYv1QS16dZGvvFoCbaEtVfnl5qS7uHQJ8ebOVS5J47goAALCBGQBAZ6NR
DcaDXJnkxN4twDFxZhvkd0ZLdUbvEKbD8mJdkuTF8TwO2HhaKj+9vFiX9w4B/rPRQp2V5H/07gAAAODW8cIxdHbomvxYEvcJh+n2NePkzU9bqh29Q9jYlhfr
J5I4OAM2uktWFuunekcA/954kOcn2d67AwAAgFvHAAA6uuz8un9Lntm7AzgOKg+aq/zK6BG1pXcKG9PyUj07yf/s3QFwNFTy1OXF+uneHcBhK0v14FTO690B
AADArWcAAJ3s3l3DwSCvSLKtdwtwfFTymPFZeXlSrXcLG8vyQv2PVPb07gA4yi5eXqxR7wggqcrzk3iOCgAAMAUMAKCTk/fmWUm+tncHcNwtrixl1DuCjWN5
sZ6Slp/s3QFwjDxzz2Jd1jsCNrNnLNajknxL7w4AAACODgMA6GBlsb4pyf/o3QH0UZWVPYv1/b07WP+Wl+rJSX6mdwfAsdSS5+xZqqf37oDNapL8r94NAAAA
HD0GAHCcjeZrWyUvjb9/sJm1lly5slD37R3C+rWyVBemckVcjhfYBFrl8uWl+pHeHbDZ7Fmq70rykN4dAAAAHD0OIOE4vIA68QAAIABJREFUGw9zSZJ79e4A
ujthkrxpdF59Ve8Q1p89SzVflZfFczVg82ipvGh5sX6wdwhsJq3cmgoAAGDaeFEZjqPlC+quSS7t3QGsD63lzodm8vrRI2pL7xbWj+Wl+r5WeW2Smd4tAMdZ
S/LiPUu11DsENoPlxXp0kq/v3QEAAMDRZQAAx1FbywuTzPXuANaPljxy7aw8v3cH68Oe8+ubc/jw3ygE2KwGrfLy5cX67t4hsAlc0jsAAACAo88AAI6TPQv1
hEoe07sDWH8qeerKQj2pdwd9LS/Vvdogv5Fk2LsFoLOZJK/bc349qHcITKuVhfqGJI/o3QEAAMDRZwAAx8FooU5qLT/VuwNYv6rl5x10bF6X/kCdXpU3JTm1
dwvAOrG9DfIbe86vO/UOganU3JoOAABgWhkAwHGwljwrye17dwDr2mwb5KrRfJ3WO4Tj6+L5mps5lDe15G69WwDWmdsNBnnb6MI6pXcITJM959edKnGbDQAA
gCllAADH2KXn1T3r/2fvTsMkK8v7j//uU9WzMGyGTRQEBUUlbnEXlTFuSNx1VJiFUZMxGsGg/APMgkeme4ZNCaLR4MIw3T1g2mjc4hJURIxLgKgBAZFFZd+G
bZjp7qpz/18wJm4IVX3Oueup+n6uq19kJKe+XJfH01PPfZ7H9M7oDgBJeFR7tj4ZHYH65Lln82Zrg6TnRLcAQC9y6Ymtlj6fL/BZ0S1Av7BMf6f7j9oAAAAA
APQhBgCAijUbOkXSUHQHgDS49LqVi/wd0R2oR/tKnSrptdEdANDj5rfm6EzJLToESN2RC3yupLdFdwAAAAAAqsMAAFCh4w71F7n0V9EdAJLzj8uX+JOjI1Ct
lYv9SDcdEd0BAElwHbpioVZFZwCp23aO3ixpp+gOAAAAAEB1GAAAKpLnnhUNnRzdASBJc7K2Nmx9Qwt9aOVCf6WcZwQAdMJM+YqFflh0B5AyF8fTAQAAAEC/
YwAAqEj7Si2V6+nRHQASZdp/m9k6KToD5Vu+xJ8s02fE2bsA0Ckz0xkrFvpzokOAFK06zPeX61nRHQAAAACAajEAAFQgX+bbeKY8ugNA2kx694pD/TXRHSjP
P7zNt2u4PiNpm+gWAEjULDN9bvki3z06BEiNF3prdAMAAAAAoHoMAAAVmN6s98q1Z3QHgPRZpk+tWOKPjO5AGdxmTWqdux4fXQIAidvdTOP5fG9GhwCpyOd7
U65DozsAAAAAANVjAAAoWb7UdzTX+6I7APSNnazQesktOgQzs2KRjpXp9dEdANAPzPWi1h4aju4AUtF6pA6SxM4ZAAAAADAAGAAAStZq6yhJO0Z3AOgrf7lq
sf4mOgLdW7nY/9Kk46M7AKDP/MPKhf7G6AggCabF0QkAAAAAgHowAACU6NglvpNcR0R3AOg/7jo5X+h7RHegcyve4nvKdY6kRnQLAPQZk+nMlYv9CdEhQC/L
l/k2kv4qugMAAAAAUA8GAIASNQodLWm76A4AfWn7tunj0RHozLJlPmRNnS1pl+gWAOhT28r1+Xyhbx8dAvSq1iYdLGledAcAAAAAoB4MAAAlOfatvoukd0Z3
AOhfLv3VqsX+lugOPHS73qfTJB0Q3QEAfW6/VqYzoiOAnpWJozIAAAAAYIA0owOAlJj0olWL/Y++OeFTerlM29bdBGCwuOu0/BA/Nz/bbotuwZ+2aqEf6gyG
AUA9XG9eudC/Nzxup0enAL0kX+pzWi0dHN0BAAAAAKgPAwBAZ97urrf/0f/Eai4BMKh2bTV0qqTF0SF4YPlC36Nl+kh0BwAMFNPJy5f4d9ast59GpwBB9lux
yP/5t/+g1dKu4pg6AAAAABgoHAEAAEB6Fq1c5K+OjsAfl+eetUyjkh4W3QIAA2Z21taGfKnPiQ4Bguxu0rLf/pH02ugoAAAAAEC9GAAAACBNH8uX+o7REfhD
01fpKEnzozsAYCCZ9m9P6wPRGQAAAAAAAFEYAAAAIE2PaLf1/ugI/K5Vh/n+5iw8AUAkNx21cpHPj+4AAAAAAACI0IwOAAAA3XHXu5cv9k+tGbVLolsgHX64
z/aNOlsSW0+jV7Uk3Sbp1q0/UybdI0ku3e1S20yTct0n17ZuGjJpyKRtt/4zO0iaJdcuMu0iaWcxUIzelLnrzKMX+FNPnLC7omMAAAAAAADqxAAAgH7R0v8t
YmyUpMw05dKm3/wDJs0rXLNMakjafusfbytpqO5YoCTNzHWypFdEh0Da4U6NSHpSdAcG2p2SrpTpSrmuNNfPlen6VqFbNUu3rj3Tbi3zw/Lcs6krtIua2iVz
7WzSo+R6rGd6rFyPlfRYSduV+ZnAQ2WmvYdm68OSDotuAQAAAAAAqBMDAAB6XSHp1266Wq6rzHWtSTe66TZz3e6m25qTujWfsDu6/YB8gf/ZZFO7ZkPa2Qrt
LGk3SbtK2kvSvlt/HlnKvw1QvoNWLvRXDo/bl6NDBtlxh/qLCteR0R0YGG7SlS79l5t+JNPFRUNXlL3A/2Dy3ApJN2/9+eP/zFJ/eLut/Vz6C7meKelZkvap
qxEDb8nKhf6l4XH7bHQIAAAAAABAXSw6AP9n1WK/zF2Pj+4Aorh0tUkXy3SxpJ/IdVVzUtfkEzYV3ZYv822mtmjfzLWvXPtLeoakZ0raPTgNkKQrm5P68164
VwZRvtR3bLX0E0mPim5B35p06QKZzmtI/zXV1o9O2GAbo6O6dewS36lR6Jm6/zk6X9IBkmaHRqGf3d5s6cn5OXZDdEg/WLHQzzTT0ugOAD3ns5IujI6o2Gsl
PSc6Ag+RaUR+/y6RqIjpv4ZH7VvRGQAA4I9jBwAAUe6R6TtynS/TRc2GLs7X2Z3RUQ8kP8Puk/TTrT+f+82fr1jij1RLz8hMzygyHWCu54lFDNTvsa3Zeo+k
k6NDBlGrpdPE4j9KZqbLVegbnunrzbk6b+tzqC+sXW+3S/ra1p/VRy32eXOkA+V6mZlezkAsSrbTdFOflHRwdAgA9LF/Hx6zM6MjqrRyke8lBgCS0WzoI/k6
uym6AwAAIAoDAADqslnSxZIuUKZzm5t1fj+8rTyy3q6XdL2kL0jSkQt87ry5OkCFXiLTS+T6C7HbCuqxavkiH1szZjdGhwySlYv9L+VaHN2BvvFDd50j1+eH
N9gvo2PqcsqobZL071t/lC/xR027XmuF3iLTc8RzFDNk0itWLPJDRsbs7OgWAAAAAACAqjEAAKBKd0n6srv+9b4pfe3UCdscHVS1rf+O52790fJDfLesqVe6
680mvUj87y6qs52ZhiW9PTpkUBx+uM+2O/VRZ3ESM2DSz1yaaGfasHa9/Ty6pxfk6+1Xkj4s6cMr3uJ7WlOvl7RA9x8VAHTFpFOPOdS/lvLxGQAAAAAAAA8F
C1EAynanmz7nrs/d8zCde/rpNhkdFGnN2XazpE9J+tSxb/Vdmi29oZDeZK4XSmoE56HPmGvpisX+sZFR6/fzN3vCDht1rIutytGVe1wa9Uz/vGa9/TQ6ppeN
nGO/lnSapNNWLvYnmLTMXUsl7RhbhgTt1sy0VtLfRocAAAAAAABUiQEAAGX5rps+cd8WfXYQ3vTvxtoz7VZJH5f08eWLfHeT3mrSMkl7Baehf2Tm+qCkA6ND
+t3KQ/2xko6O7kBaXPqFSZ9sFTqDt5A7Nzxql0k6Ml/qx7ZbepNL75X0lOguJOVvVi300dXj9r3oEAAAAAAAgKowAABgJm6VaX27pU+uPdsuj45JydZz2tcs
WOAn7jdLr5DpnZIOkpQFpyF9L1y50F82PG7fiA7pX27K9HFJc6JLkAaXvtqQTj1+TOdK5tE9qcvX2RZJ6yWtX7XIXyDpPS69TjxD8eAyN31s2TJ/+hln2HR0
DIC+cqukGyRdL2mjXHeatLEwbTRpo5vulSS1NWVNbfr9/+fM1WhL2//v/11oSJm2LaQdM2meXNsU0vZ2/888l3aQayeZdpK0k6Shev41AQAAAKSAAQAA3bjG
XKfcO6Uzedt/ZiYmrC3py5K+vHKxP1quwyW9Q9I2sWVIWqbVkv8HC43VWLVIi136y+gOJMB1rmVaOTxqP4xO6Verx+y7kr676jDf31s6WqZDxRE7+NOetMsm
vU/SCdEhAJLS0v1/D/6ZpCskXVG4fjGU6QY1dd3W4bQw+ULfvpVpJyu0c1vauZFpt0LaQ67dMteebtpN0h6SdhPDAgAAAEDfs+gA/J9Vi/0yd84SRk+7xKST
G9dpQ36etaJj+lV+iO/caujdkv5e0g7RPUiTm149Mmpfiu7oN/kC/7PWbF0madfoFvS070laOTxm50WHDJpjF/oTG9IxDALgQWxWQ08aPsuuig5JzYqFfqaZ
lkZ3ABXbLOknLl2YmS5SoYsaU7oin7Cp6LCZynPPpq/W7llbexemvc21tzLt5a69JT3apL3V3ctCbxseszNLje0xKxf5P0l6Z3QHHppmU7vn6+ym6A4AAIAo
7AAA4KH4qVwrhsf1Fd4orl5+tt0mKT92iZ/eKPQeSUeIQQB0yFyrJf8y92y5pmfrRGPxHw/sQs905Mh6uyA6ZFCtHbefSVqyfLGfZIVOMdPLo5vQk+aqrY9I
ekV0CICesNFc57vp20Wh78y6QZf068B7nluh+48puF73Dyz+7n++wGe15mgfL/R4Mz3OTY8z1xMl/bmkbWvOBQAAANAlBgAA/CnXm+n4y7foU1u3qkeN1q63
2yUdd8yhfmoz09GSjpQ0KzgL6XjKisV648ioJqJD+sWKJf58K/T26A70pJtlWtHcR2du/WIdwdaM2iWSDlq5yF/t0gdN2je6CT3noBUL/c0j4/aZ6BAAtWu5
6btW6CvW0Lcaj9FPeH7fb+suB5dt/fm/P889a/1c+3hDT81cTy2kp5n0PDGoDgAAAPQkBgAA/DH3SvrgpkmdeOqEbY6OGXQnbLCNko5ZucjPlOkUuV4Z3YQ0
ZK7hfL5/vl/fYKqXmxU6VRyfhN81ba6PTU3puBMn7K7oGPyh4TH74rJl/tVd79O7JB0vafvoJvQOM52SL/Mv5WfYfdEtACq3UdLXzPTFRkNfy9fZndFBKdk6
IHHl1p+J+//Ms6mr9eeZ6wVe/O7AAAAAAIBYDAAA+H3rm229b+s29Oghw2N2haRXrVzsB8v1IUn7RTeht7n0uOk9dYik0eiW1K1aqENcekZ0B3rKD2R62+ox
4wvvHnfGGTYt6bTli/xfGtJHXXpddBN6xh7Tm3SEpBOiQwBUYotM57q0fmiLvrD17XaUZOtQwE+3/gAAAADoIVl0AICecY1cLx8es8NY/O9tw6P277dsoydJ
OkYSX2LhTzLX+5ct86HojpTlS32Om9ZEd6BnTEv6wBWTev7wKIv/KVkzZjeuHrPXu+lNkvhdB5IkMy1ffojvFt0BoDTupm+7a2nTtdvwqL1qZNQmWPwHAAAA
MEjYAQBAy1wfaszTB9j+NB1b32Y8cdWhfq5n+rSkJ0c3oWfts9t9OkzSJ6NDUtVq6T2S9oruQE/4aVHosDUb7MfRIejeyKhNLD/Ez2809DF2A4Ck7ayhlZIO
jw4BMCN3ufQZN52+ZtQuiY4BAAAAgEjsAAAMMJN+boWes3rcjmbxP02rN9hFzUk9U9IHdP9bqcAfKKSjFyzwRnRHivJDfGfdv9sGBlvbTMffso2eweJ/f1hz
tt28esxe766lku6J7kEsk96xcpFztBKQpp+4a+mmSe0+MmbvYPEfAAAAANgBABhcrtHGlN6VT9i90SmYma3bWebLF/kXM+lfJO0T3YTeYtK++83RayR9Lrol
Na2mjpNrx+gOhLotMy06ftS+Hh2C8o2M21nHLvHvNwp9VtKTonsQZshcJ0p6bXQIgIfse246cWRUX5bMo2MAAAAAoJewAwAweO52adHwuC1h8b+/rBmzi5uu
vzBpIroFPch5i71T+aH+GLneEd2BUBc2m3omi//9be16+/mmST3bTZ+ObkEcN73muIX+4ugOAA/qi2Z6zvCYPX9k1L7E4j8AAAAA/CEGAIDBcmGzqaeMjNl4
dAiqkY/b3avH9GaZ3iuOBMDveuaKJf786IiUtEwnS5oV3YEYLp3RnNQB+Tq7NroF1Tt1wjaPjNrbTTpM0uboHsQoTCfnufN3ZKA3fc8LHTg8Zq9ZPWo/jI4B
AAAAgF7GlxvA4Dhn06ReyELGIDAfHrVT3fVCSTdG16B3ZG0dFd2QilUL/QCZXh/dgRDT7lo6Mmbv2HrECgbI6jFbb6YXSbo5ugUhnta+Um+JjgDwOy7MpJcN
j9nzRzbY+dExAAAAAJACBgCA/ueSThwe06GnThhvtA2QkXH7QbOlZ0i6OLoFvcFNr1652J8Q3ZECN50U3YAQdyvTwSPjdlZ0COKsHrUfyvRcM10e3YL6FdJI
vsDZ/QWId7ukv2/uq2cfP2b/ER0DAAAAAClhAADob5vc9YbhMTuGsxEHU36O3dCc1IEmfSm6BT3BJB0ZHdHrjlvkL5X0vOgO1O5GyzR/eL2dGx2CeMOjds10
W8+TdF50C+plpr3bs7UkugMYYC1zfXh6UvsMj9lpeW5FdBAAAAAApIYBAKB/3VJILxwZt89HhyBWPmH3Xj6p18n10egW9ADX4uWH+G7RGb2skFZGN6Bmrkub
mZ6zer39d3QKescJG2xjc1IvlzQW3YJ6ubRy2TIfiu4ABtD3rKGnrh6395w4YXdFxwAAAABAqhgAAPrTryS9cM2YsfU7JEkTE9YeHrd3u+no6BaEm9PI9O7o
iF61arEfKOmF0R2o1Q+bQ3p+vt5+FR2C3pNP2NTwmJbIdHp0C2q1126btTA6AhggmyUdc8WkDlx9ll0aHQMAAAAAqWMAAOgzZrrcW3r+8JhdEd2C3jMyaieZ
dLgkjoQYYG5651GLfV50Ry8qXKuiG1CrC1uFXpGvszujQ9DLzIdH7Qi51kaXoD7uWpnP92Z0BzAAvtfO9NThMTtxYsLa0TEAAAAA0A8YAAD6y8UN6cCRc+zX
0SHoXavH7CMmLZPEeZqDa6e5hd4cHdFrViz055j04ugO1OY/m64Xn7DBNkaHIA3D47bcXMPRHajNPtN78KwEKjTl0vuGx/SCtevt59ExAAAAANBPGAAA+sfF
zaZenI/aLdEh6H2rx+yTbloqibdsBpSblkU39BozvT+6AbX53tQsHZSP293RIUjL6nFbZabjoztQD5NW5Lnzd2agfL+0TPNHxuxDkrEzGQAAAACUjC8zgD5g
0s/aQzqILYzRiZFRGzXXErETwKB69qpF/pToiF6xYrE/Q9JB0R2oxQ+akzropE/bPdEhSNPqUXu/mU6I7kAtnjB9pRZERwB9xfW5VqGnrV5v349OAQAAAIB+
xQAAkL6rGi29dO2Zdmt0CNKzetw2SHp3dAdiFGIXgN8w16roBlTPpV80Ta/JJ+ze6BakbfWolkv6VHQHqpeZjmMXAKAUbUnHDI/bGzh+BwAAAACqxRcZQNqu
l+ml+Tl2Q3QI0jU8Zh+T9IHoDtTPpIVHLfZ50R3Rtu6E8KroDlTuxqGmXspROSiH+RWTeodcn4suQbVceuL0L/S66A4gcXfL9drhMTsxOgQAAAAABgEDAEC6
Nsr00uFRuyY6BOkbHrNcro9Gd6B2O8wt9OboiGguLZdk0R2o1N1FoYPzdXZtdAj6x8SEtTdNaZGk70W3oFomrYhuAFJl0s/bbT17eNy+HN0CAAAAAIOCAQAg
TdOZa8HwqF0WHYL+0XysjpDpM9EdqJfbYB8DsOItvqek10d3oFJTMr1uzQb7cXQI+s+pE7a5OalXm/Sz6BZU6mmrFvuB0RFAgr4zNalnrT3bLo8OAQAAAIBB
wgAAkCAzHXH8uH0zugP9Jc+taDa0VKYfRbegVs9etcSfFh0RxZr6O0nN6A5Ux0yHD4/at6I70L/yCbuj0dRfSbotugXV8UJHRDcAKTHXFzZN6hUnTthd0S0A
AAAAMGgYAAASY9Ipq0ft49Ed6E/5OttSuF4r6froFtSnKPTX0Q0Rjlzgc6XB/HcfIGetHrUzoiPQ//J1dm3meoukVnQLKmJ6zcrF/ujoDCAF7lrXuF5vPHXC
Nke3AAAAAMAgYgAASMsXG/vq6OgI9Lc1Y3aju94oaTK6BfUwaeFRi31edEfd5s3SIkk7RXegMj+462F6R3QEBsfx4/ZNl46N7kBlGnK9MzoC6HVmOmFk3N6a
n2cMRAEAAABAEAYAgHRcNT2pJXluRXQI+t/IuP3AnYWzAbLDXNcboiNqZ3p3dAIqc5NneuPppxuDTKjVyJidIunM6A5U5m8GcWAOeKi27lbHIBQAAAAABGMA
AEjDpBV6M+cnok4j43aWS/8U3YF6uHRIdEOdjjvUXyTpydEdqETLpTeMrDeOMkGITZP6O0k/ju5AJXac41oUHQH0qJNXj9n/i44AAAAAADAAACTBXO9dvcEu
iu7A4Ln7YXqvWMQYFC9ZfojvFh1RlyLTEdENqIgrHxmz/4zOwOA6dcI2N6UFku6JbkH5TDpCcovuAHqJmU4YHrN/iO4AAAAAANyPAQCgx5k0sXrceAsbIU4/
3SZV6E1iEWMQNBvZYBwDsOJQ30vSq6I7UIkLrpjSCdERQD5mv5DrfdEdKJ9LT1y5RC+O7gB6hukTbPsPAAAAAL2FAQCgh7l0dcP119EdGGzDG+xKc/19dAeq
5zYYxwBYQ4dLakR3oHR3NZtaPDFh7egQQJKGx+0Tks6J7kAFXO+JTgB6gunLzV/rXdEZAAAAAIDfxQAA0LuKzPS2fNzujg4BVo/bpyWNR3egcgfkS33v6Igq
HbXY58n1tugOlM9Mf5uvs2ujO4Df1ir0Lkm/iu5AyVwH54t83+gMINgPt0hvyc+zVnQIAAAAAOB3MQAA9CgzfXj1qH0nugP4jabrXZKui+5ApazV0oLoiCrN
LvRGSQ+L7kDpxlaPGm9ao+ecsME2eqHFkoroFpQqa5veHh0BRHHpF81JHXzKqG2KbgEAAAAA/CEGAIDedMW9W7Q8OgL4bfm43V1Ifxvdgcr19TEAZloa3YDS
3dYe0nujI4AHMrLBzpfrY9EdKJe7lixY4Bwng0F0j5tel0/YHdEhAAAAAIA/jgEAoPcUnumvT52wzdEhwO9bM2ZfkXR2dAcq9bRjF/oToyOqsOJQ30vSC6M7
UC4zHb72TLs1ugP4U7ZkOlrSNdEdKNUj9putl0ZHADVzud62ZtQuiQ4BAAAAADwwBgCAXmM6dWS9XRCdATyQZltHSGKxrY81M705uqEKlmmp+N2nr7j0Vbb+
RwpOGbVNhevvojtQMnaVwYBx03HD4/bZ6A4AAAAAwJ/Gl+BAb7mxWej46AjgT8nPttvcdXh0B6rjroXRDeVzk7Q4ugKl2mTGgirSsWbcvirThugOlMj1mmMO
9YdFZwB1cNfXR0Y1Et0BAAAAAHhwDAAAPcRdR+bjdnd0B/BgRsbtM5K+Ft2ByuyzfIk/OTqiTCsO1Qsk7RPdgfKYdMzwqLGlOpLSburvJd0W3YHSzBkyHRId
AdTglqEhLZXMo0MAAAAAAA+OAQCgR7j0za2LqkASmtLhkiajO1CNrK1XRTeUaev2/+gXrksb1+nj0RlAp9aeabeaaVV0B8rjmQ6LbgAq5oX0tnyd3RQdAgAA
AAB4aBgAAHrDlBlbqiMt+Zj9QqaPRHegIqZXRieU5ajFPk/SG6M7UJ7MdGR+nrWiO4BuXL5Fn5D0k+gOlMT1rFUL/UnRGUCFTlkzZl+JjgAAAAAAPHQMAAC9
4bThUbssOgLoVLPQ8ZJuju5AJZ6VL/ZdoyPKMNf1BknbRXegNP92/Jj9R3QE0K2JCWtnhY6M7kB53LQ4ugGogpkubzZ1XHQHAAAAAKAzDAAA8Ta2Cq2NjgC6
kY/b3ZKOje5AJbK2dHB0RBlcbM/cR6bamY6OjgBm6vgN9m2T/jW6A6VZsmyZD0VHACUrCtfb83W2JToEAAAAANAZBgCAaK6REzbYxugMoFvNfXWWTBdFd6AC
nv4xAPkSf5Sk+dEdKInp9LXr7efRGUAZ3PT/JLGw1h922/k+vSw6AiiTSR8aGbP/jO4AAAAAAHSOAQAg1vWbpvRP0RHATOS5FXKtjO5A+Vx6+eGH++zojpmY
LvRG8ftOfzDd0WxoODoDKMvwqF1jrg9Hd6AcmfSm6AagLC79orGN3h/dAQAAAADoDl+IA4HMtPLUCdsc3QHM1PCYfU3Sd6I7ULptd7hDB0ZHzIS53hjdgHK4
64P5OrszugMoU6uhkyTdHd2BUrw6X+CzoiOAMrjriPwMuy+6AwAAAADQHQYAgCBmurzxa41FdwBl8YxdAPpSlu4xAPlSf7hMz47uQClum56l06MjgLKtXW+3
SzotugOl2LGYoxdFRwAzZvrymnH7anQGAAAAAKB7DAAAQQrXyvw8a0V3AGUZWW8XuOvr0R0omac7ANBq6w3id51+cdJJn7Z7oiOAKkxP6oMy3RHdgZlru14f
3QDM0JRcR0VHAAAAAABmhi/FgRhXDO2rz0dHAGXLXCskeXQHSvXoVYf5/tER3XDpDdENKMVNzW300egIoConTthdKvSh6A7MnEmvz+d7M7oDmIHThsfsiugI
AAAAAMDMMAAABDDTCXluRXQHULbVG+wiSWwZ2me8rYOjGzqVH+I7m+sF0R2YOXedyDnE6HdbMv2jpFuiOzBjO7f31AHREUCXNk5PaiQ6AgAAAAAwcwwAAHUz
/bqxRRuiM4CqeKEToxtQLld6Zxq3G3qtJN7CTN/tk5k+ER0BVO2UUdvk0mnRHZg5dp9Bqlw65cQJuyu6AwAAAAAwcwwAAHUrdHI+YVPRGUBVRjbY+XJ9P7oD
5THpBcuW+VB0RycKcQ5zn/jIKaO2KToCqEO70Mck3RPdgRlyvV5yi84AOnTb9CydHh0BAAAAACgHAwBAvW7fkunT0RFA1Vw6OboBpdp2l016enSRH/wmAAAg
AElEQVTEQ3X0At/BpBdHd2DGthRtfSw6AqjLCRtso5k+Fd2BGXvkioV6dnQE0BHXCSd92hhAAgAAAIA+wQAAUC/eZMRAGBnXv5n0s+gOlMeydI4BmDVLr5I0
K7oDM+OudWvOtpujO4A6NQp9UNJ0dAdmxoxdaJCUm5vzGLgDAAAAgH7CAABQn2nnHGMMDHM3fSi6AuVxT2cAwKXXRTdgxgoz/WN0BFC3fNyuk/Qv0R2YGZfe
EN0APFRu+kh+ht0X3QEAAAAAKA8DAEB9Pj+y3q6PjgDqsmmLNki6PboD5TDpgMMP99nRHQ9m2TIfkuml0R2YGXN9aXjMrojuACIUhU6JbsDMmPSYYw/xx0d3
AA/BfUMtfTw6AgAAAABQLgYAgJp4oY9GNwB1OnXCNpt0VnQHSrPN9nfpmdERD2aXe/VcSdtFd2BmTDo9ugGIsmaD/VjS+dEdmJmsqZdFNwAPwVn52XZbdAQA
AAAAoFwMAAB1cF06skHfjc4A6uYN/ZOkIroDJXHNj054MBlv//eDq7LH6tvREUAkc/1zdANmxsTzCD3P2219ODoCAAAAAFA+BgCAGlimD0vm0R1A3YbPsqvk
+lZ0B8phrhdFNzwYz3jjsg/8c54bg0MYaI0pfVbSLdEdmAHXi1I4OgeDy13fWHu2XR7dAQAAAAAoHwMAQPU2TQ7p7OgIIIob54r2kefmS31OdMQDOeZQf5hc
T4/uwIxMNY2jQ4B8wqbMtS66AzMyb4eNem50BPCAMn0qOgEAAAAAUA0GAIDqff6kT9s90RFAlKHr9AVJN0R3oBRz2209OzrigTQaeomkRnQHZuRf81HjrWdA
UuP+YwDYDSNlzq406Fm3372jvhgdAQAAAACoBgMAQMUyaX10AxApP89akkajO1COQnpBdMMD4bzl9Jlx7jnwG/kGu1rSudEdmAGOpUGvMq07/XSbjM4AAAAA
AFSDAQCgWtdfNsn550DbGYTpF+Z6ZnTDA+JNy9RdtXpU50dHAL3ExBbdSXM9LV/su0ZnAL/PMp0Z3QAAAAAAqA4DAECFzDQ6MWHt6A4g2tpx+5mkH0d3oBTP
ig74Y1Yu8v0k7RXdge6ZaVwyj+4AekmjqS9Kuiu6A13L2oVeEh0B/J7/WX2WXRodAQAAAACoDgMAQIXa0nh0A9AzXGPRCSjFw/OFvkd0xB/g7f/ktQp9JroB
6DX5Otvirs9Hd6B7BcfToPdMRAcAAAAAAKrFAABQnYvXjNol0RFAryhMGySxI0YfaGW9twuAGQssibtw604hAH6PNRgoTZmZDpLcojuA/2X6bHQCAAAAAKBa
DAAAVeGLFeB3rBmzGyV9M7oDM2fSM6MbftuCBd5w6cDoDszA/QNCAP6I5mP0LUnXR3egaw8/dqGeEB0BSJJclw6P2mXRGQAAAACAajEAAFSk3WK7VuCPOCc6
ADNXeG8NADx+rp4safvoDnStcNO/REcAvSrPrTDp7OgOdK8hHRDdAEiSib+jAgAAAMAgYAAAqMYla8+2y6MjgF7TzvRFSa3oDsyMSc/Ic++Z3yG80HOiGzAj
542sN95uBv6UjF0ykmZ6bnQCsNXXogMAAAAAANXrmS/vgX5ips9FNwC9aO16u91N343uwIztMHmFHhcd8VueFx2AGeCZCTyo1evtv126OroDXeM5hV5w983z
9KPoCAAAAABA9RgAACrQNv1rdAPQq6xg69F+kDV75xgAZ2ElZe7T+mJ0BJACk74Q3YCuPe7Yt/ou0REYcK5zzzjDpqMzAAAAAADVYwAAKN9Va9bbT6MjgF7V
bOgLkjy6AzPkelZ0giQtP8R3M+kx0R3o2kUj59ivoyOAFJgxAJAwy1ocV4Ngpm9EJwAAAAAA6sEAAFAyc30lugHoZfl6+5Wki6I7MDOm3tgBIGvqgOgGdM9Z
0AQessu36AJJt0Z3oDtW6LnRDRhwhb4VnQAAAAAAqAcDAEDJPNPXoxuAnuf6t+gEzNhTFizwRnSEOQsqKXPxvwXAQzUxYW03fSm6A10yjqtBqFuGN9iV0REA
AAAAgHowAACUa7K5RedHRwC9jkGZvjBnv6H4rfddLKgk7Ko1o3ZJdASQGIZm0vWsfIHPio7AwPpBdAAAAAAAoD4MAABlcn03n7B7ozOAXje0jy6WdEt0B2Yo
0/6RH3/44T5b0l9ENmAGTP8enQCkZmiuvilpS3QHujK3PUtPiY7AgDIGAAAAAABgkDAAAJTIjbeagYciz62Q9M3oDsyQxw4AbL9RT5c0J7IBM1DoG9EJQGry
M+w+uS6I7kB3nGMAEMX1/egEAAAAAEB9GAAASuSmr0U3AKkwY/EveRY7ACC2/09ZqymOzAG64Zn+I7oBXTI9NzoBA8mnZumi6AgAAAAAQH0YAADKc8OaUV0a
HQGkojGtb0jy6A7MSOgAgJmeEfn5mJHv5+N2d3QEkKLM2XEqWa5nRSdgIF170qftnugIAAAAAEB9GAAAynO+ZCxmAg9Rfo7dIOmS6A7MyH75fG9GfbiJs5QT
xhvMQJdWj+mnkm6M7kBX9s6X+o7RERgsxu/bAAAAADBwGAAASmKu70Y3AKkx0zejGzAjs1t7aJ+IDz5ygc9112MjPhsz584AANA9c4nnZ6JsutCfR0dgsLgz
AAAAAAAAg4YBAKAk7YyzjIFOFa4LohswQxZzDMC2Q3qipEbEZ2PG7hy6XhdGRwApc9M3ohvQnaytJ0c3YLC4cUwdAAAAAAwaBgCAMpjumLWPfhadAaTG2wwA
pM6lJ4Z8bkNPjfhclMB0QX6etaIzgJQNFfp2dAO6UxjH16BeLl0W3QAAAAAAqBcDAEAZXBfkuRXRGUBq1pxtN0u6MroD3TOP2QHACt6gTJUX+l50A5C6fNyu
k/Sr6A50zsTzC/UqCl0T3QAAAAAAqBcDAEAJXPpudAOQMHYBSFvIAIAbCyjJanDPA6Uw7qVEPSnPnb+Hoy73nLDBNkZHAAAAAADqxRcPQBk4xxzomnH/pG6/
fL43Az73SQGfiZmbHMp0YXQE0A+M3TRSNa/1c+0THYGB8cvoAAAAAABA/RgAAGZu+r4p/SQ6AkhVi7eBUzertaf2rPMD84W+h6Sd6vxMlObCfJ1tiY4A+kGb
52e6TE+JTsBgMAYAAAAAAGAgMQAAzNzPTp2wzdERQKrWrteVkm6P7sCMPLrOD5ti4SRlLFgCJZn1GF0iia29U8QxNqhJ4fp1dAMAAAAAoH4MAAAz5NJ/RTcA
aTN36eLoCnTPCu1d6+c52/+nygt9P7oB6Bd5boWkH0Z3oCsMsqEWWaZbohsAAAAAAPVjAACYocx0UXQDkDpzzgRPmVvNAwDsAJAsz/Sj6Aagn5hxT6XInR0A
UA933RHdAAAAAACoHwMAwEwVDAAAM+UM0qSu1iMAJD2x5s9DOW5aM2Y3RkcA/cSd52eKzLRXvsC3je5A/3NjAAAAAAAABhEDAMDMTDeG9D/REUDqhposYCSu
xgEAN0n71Pd5KIuJ+xwom2fcV4my9myeZaieSbdHNwAAAAAA6scAADAzl+brbEt0BJC6fJ1dK76gTNnedX3Q8kV6uKR5dX0eSsROH0DpRtbb9ZJuiu5A5wpp
3+gG9D8v2AEAAAAAAAYRAwDATDhv/wNlceni6AZ07RH5Up9Txwc1WDBJlrv+O7oB6FM8P1Nk7ACA6mXSpugGAAAAAED9GAAAZsCln0U3AP3CpB9HN6BrNlno
UfV8EgsmqWpmLFICFWF3jRQ5zzNUz01T0Q0AAAAAgPoxAADMRKZLoxOAPnJZdAC612jXdAxAwYJJom7L19uvoiOAPsVwTYKMHW1QBwYAAAAAAGAgMQAAzIBl
7AAAlMWM+ylppkfX8TFuLJgk6pLoAKBvNTiSKlEMtKFy7AAAAAAAAIOJAQCge5uvuE/XRkcA/aKxRZdK8ugOdMesph0AWDBJEkfmANVpPlrXSLovugMd2/Pw
w312dAT6W9FgAAAAAAAABhEDAED3Lp+YsHZ0BNAv8gm7V6brojvQHVc9OwCILZOTlHHEB1CZPLdC0hXRHehYtu1ttT07MaB8Uq3oBgAAAABA/RgAALp3aXQA
0G+84C3hZLkeUfVHHHOoP0zSw6r+HJTPOeIDqBr3WIKswa42qNacWeyuBQAAAACDiAEAoHs/jw4A+o2xSJgsk3ar+jOGjLf/U9VscG8DlXJ22UhRxq42AAAA
AACgAgwAAF0y1zXRDUC/MdPl0Q3ojku7Vv0ZBQMAqbozX2c3RUcA/czZASBNxg4AAAAAAACgfAwAAF0qTFdHNwD9hsGapO2YL/U5VX6AuR5T5fVRGRYmgYqx
g06a3BlsAwAAAAAA5WMAAOjSUJMBAKBsRYP7KmXTW7RLpR9gemSl10cl3DkyB6ha8zpdJakV3YHOmLRHdAMAAAAAAOg/DAAA3dmcr9PN0RFAv2n+Ur8UCxjp
GtJuVV7eXI+o8vqohrFjDlC5/DxrSfp1dAc6tnt0AAAAAAAA6D8MAADdcF0tmUdnAP0mP89a7rouugPdca92AMAzFkpSxNEeQD1cDNskaKd8gc+KjgAAAAAA
AP2FAQCgC7zNCFSH+ytdjYoHAMSbkqliAACoAc/PJNl0o/JnJwAAAAAAGDAMAABdcNO10Q1Av+INxnR5VuUihpuqHzBABRptBgCAmnCvpYjdbQAAAAAAQMkY
AAC64bo+OgHoYyxgJMqkXau6dn6IdpLENsnp2aLH66boCGAQeMEAXaIYAAAAAAAAAKViAADogjEAAFQmk66LbkB3vMI39Nu8IZkkM12b51ZEdwADwRmgS1HW
4PkGAAAAAADKxQAA0AWTboxuAPoV91fSKhsAcM5ITlJR6JfRDcCgGHJ2AEgUAwAAAAAAAKBUDAAAXSgy3RDdAPSrljEAkKwKdwCwQo+o6tqojhk7egB1yc/W
7ZK2RHegM84AAAAAAAAAKBkDAEAXmg0WKIGqzNrCgE2yTDtXdWkWSNJkzvMSqI+5u26KrkDHeL4BAAAAAIBSMQAAdO6+fJ3dGR0B9Kt8QhvFG4yp2q7Ca7NA
kiYGAIAacYxOkni+AQAAAACAUjEAAHTu+ugAoL/xBmPCtsnne7OSK5seXsl1USk3dvQA6mTcc+lxBgAAAAAAAEC5GAAAOndzdADQ71jASNeWR1S0C4Brt0qu
i0oxzAPUq2AHgBTtKrlFRwAAAAAAgP7BAADQuTuiA4B+ZwzaJGtOs7JjAHas6Lqo0FCDYR6gZgwApKf5D2/TttERAAAAAACgfzAAAHTITbdFNwD9rpBuj25A
d9pW2QDADhVdF9VxbWYHAKBOGTvoJGmope2jGwAAAAAAQP9gAADokEkboxuAfpc5O20kyytbxGBxJD135hM2FR0BDBKXboluQOcyY5cbAAAAAABQHgYAgE4V
DAAAVSsYtEmWt9kBAP+LQR6gZl5w3yWpuuE5AAAAAAAwgBgAADplfLEKVC3LuM9S5RUcAZAv820kNcu+LirHfQzUrGhw36XIGAAAAAAAAAAlYgAA6JCzNTlQ
Od5gTJdVsFX/1H28/Z8inpdA/WZPc9+lyJ3nHAAAAAAAKA8DAECHGuwAAFQuc90e3YDuVLEDgLdZGEmR8bwEandpSxslFdEd6AwDAAAAAAAAoEwMAAAdcted
0Q1Av3OOAEhZ6TsAZMbWyClyaWN0AzBoJiasLemu6A50jOccAAAAAAAoDQMAQIda0qboBqDfuenu6AZ0JyvK3wGgkfFmZIoyjgAAonDvpcZ4zgEAAAAAgPIw
AAB0KHMGAICqFS3dF92A7lRxBEDB1shJcrFjDhCEAYDEGM85AAAAAABQIgYAgA4NNbQ5ugHod7NaDNokbJvSr8gOAEmyTPdENwCDyE33RjegMwVHAAAAAAAA
gBIxAAB0ai5fqgKV21/3SfLoDHSlWcE1WRhJUMGOOUCIzNlFJzUZRwAAAAAAAIASMQAAdMbzM9gBAKhanlshaTK6A10ZKv2KzgBAkliEBEK4GL5JDTsAAAAA
AACAMjEAAHRms2S8lQzUgwWMFHn5OwCYNKvsa6J6jYwBACCCM3yTHJ5zAAAAAACgTAwAAJ1hQRKoi7GAkSKz8ncA8Cp2FUDl2sYzE4hg/L6aIp5zAAAAAACg
NAwAAJ1h+3+gJixgpKmKxfoqhgpQPS8Y4gFCMECXHp5zAAAAAACgRAwAAB1wqRXdAAwKd01FN6ALFRwBUFRwTVTP2yxCAkG491LjDAAAAAAAAIDyMAAAdCBj
AACoUzs6AF2w8hfrja2RkzR7iEVIIAg76KSH5xwAAAAAACgNAwBAB5wFSaBODNykqfRFDGdr5CRNFZqObgAGkvH8TE0Vx+cAAAAAAIDBxQAA0BkGAID6cL+l
qfwdADgCIEmzjHsYCFEwAJAadroBAAAAAABlYgAA6AxfqAL14X5LUxWLGCyMpGgL9zAQwRigSxHPOQAAAAAAUBoGAIBO8DYjUCcWD9NUxdv6LIwkaDOLkECM
jOdngnjOAQAAAACA0jAAAHTC+UIVqIuzeJiq0hcxzFkYSdFc7mEgBkcApIjnHAAAAAAAKA0DAEAnXEV0AjAwGLhJVfk7AFgluwqgavO4h4EIBcM3KWIAAAAA
AAAAlIYBAAAAUBqXGhVck4WRBN0wi0VIIIQxfJMgnnMAAAAAAKA0DAAAncjKX9gC8AB46ztJJk1XcFn+u5CgjRvZNQeIkBnDNwliAAAAAAAAAJSGAQCgE84i
FFAXY9E3TRzdgK32v1UW3QAMosIZWE2QRwcAAAAAAID+wQAA0Bm+UAXqwwBAiqrZepqhghTtzT0MhGBgNUVV7J4DAAAAAAAGFAMAQGcYAADqw/2WptIXMSo6
VgAVu7fNPQxEyHh+pojnHAAAAAAAKA0DAEAHjDPJgTpxv6Wp9Lf1nYWRJDW2cA8DITLuvQTxnAMAAAAAAKVhAADogHOmKlAn7rc0sQMAJElzuYeBGAUDAAni
OQcAAAAAAErDAADQAWcxA6gTCxgJcqtgBwBjYSRJc7iHgQj8vpoknnMAAAAAAKA0DAAAHTBpVnQDMChMmh3dgC54+QMAlVwTlZti1xwgBkcAJMedAQAAAAAA
AFAeBgCATpi2iU4ABoVL86Ib0Lkqtut3aarsa6J6szINRTcAA8kZAEiNsdMNAAAAAAAoEQMAQCecBUmgRtxvaWIHAEiSJqcZmgOC8PxMTBXDcwAAAAAAYHAx
AAB0ZnY+33mrCqgHCxgJqmIRwzIWRlJkDQYAgCDce4lxBgAAAAAAAECJGAAAOvVIvlQFqrZ10IbtwxPkxg4AuF+DIR4ghvO7aoIYAAAAAAAAAKVhAADo0JSx
oAFUbfMu3GfJ8gp2AKjgmqieGYuQQARn+CY9POcAAAAAAECJGAAAOpQV2ja6Aeh3cxssXiSs9EUM5wiAJLULBgCACBnDqukxnnMAAAAAAKA8DAAAHbKMBQ2g
ck3us1SZ657SL1poc+nXROUy3kIGovAMTc+W6AAAAAAAANA/GAAAOuXsAABUbdq0Y3QDuuNZBQMA0t0VXBNVY2AOCMERAOkx6a7oBgAAAAAA0D8YAAA6VGT6
s+gGoN81pJ2iG9ClCnYAMGNhJEWFa/voBmBAMayaGGfQDQAAAAAAlIgBAKBTBQMAQNXazn2WqiqOAGBhJE2Z9LDoBmAQuWvn6AZ0hh0AAAAAAABAmRgAADpk
7AAAVM6M+yxhpS/WZwULIykqGOQBQvAMTU/hPOcAAAAAAEB5GAAAOuW80QhUzQuOAEhVUcEOAK2MhZEUsQgJ1C+f701J20V3oDMcdQMAAAAAAMrEAADQKd5o
BCqXZQzapMoa5Q8AZA0WRpLE8xKo3576M0kWnYHOMAAAAAAAAADKxAAA0CnjzWSgas7CYbKsKH8AoDnFwkiS2AEAqF1L/J6aooKjbgAAAAAAQIkYAAA6x4IG
UDUWDpPlme4t/aIt3V36NVE5BnmA+lnBfZeihnjOAQAAAACA8jAAAHSKHQCA6rkeHp2A7riVv4iRT9iUpM1lXxfVMgZ5gNq5OEInRc4AAAAAAAAAKBEDAECn
XLtHJwAD4BHRAejOdLOyRQwWR9Kzfb7Mt4mOAAYMv6cmyF13RjcAAAAAAID+wQAA0Lnd8vnejI4A+tWCBd6QtFt0B7ri2zxKm6q4sInzkZN0L7t5ALUyBuhS
1GzwjAMAAAAAAOVhAADoXGP6USxOAlV57GztKqkR3YGubMpzK6q4sDMAkKTpJouRQM3YASBBt+/IMw4AAAAAAJSHAQCgC1mbBQ2gKo2C+ythd1R47dsrvDaq
wrE5QK3M2XUjQZtOP90moyMAAAAAAED/YAAA6ELhLFACVSka3F8Ju7nCa99Y4bVREeN5CdTKTY+MbkDHbogOAAAAAAAA/YUBAKALlrGgAVQlY/viZJl0S4XX
ZgAgTdzPQL34HTU9PN8AAAAAAECpGAAAusAbjUB1nPsrWV7hAIBYIEkVAwBATfLcM0m7RnegQ8bzDQAAAAAAlIsBAKALhbRHdAPQt1yPiU5A1yobACgYAEgV
z0ugLpfr4ZKa0RnoDDvcAAAAAACAsjEAAHTBTI+ObgD6ljEAkCzTzRVenQWSBLm0d3QDMCimZ/H8TJG7bohuAAAAAAAA/YUBAKA7+0QHAH2MBYxEWVHdAMBQ
kwWSFJn0qHy+80YyUIOs4PmZInMG3AAAAAAAQLkYAAC688h8qc+JjgD6zZELfK6kh0d3oDveqO4IgNu3042SvKrrozLN1p7aMzoCGATOAF2SOAIAAAAAAACU
jQEAoDs2Ocm2xkDZtt1Gj5Fk0R3ojrWr2wHg9NNtUtKdVV0fleLYHKAe3GsJKjJ2uAEAAAAAAOViAADoUqPJW1ZA2Qq2L05au6huBwCJtyQTxqIkUA+eoQlq
Nni2AQAAAACAcjEAAHSr0D7RCUC/MWfxImHFlS3dVukHMACQKgYAgHrwDE3PlnydsbsNAAAAAAAoFQMAQJcs40tWoAL7RQega7dPTFi7yg9gB4BEOQNzQNWO
XOBzJe0e3YGO8VwDAAAAAAClYwAA6FLhLFQCFXhidAC6dnMNn8FCSZoeHx0A9Lu5Q9pPkkV3oGM81wAAAAAAQOkYAAC6ZNL+0Q1AH2IAIFWum6r+CHNdW/Vn
oBKPX7DAG9ERQD+zjN9LE3V1dAAAAAAAAOg/DAAA3dszX+jbR0cA/SJf7LtK2iW6A91xq35x3qVfVP0ZqMSc/bbR3tERQD/LGKBL1VXRAQAAAAAAoP8wAAB0
z9qZnhAdAfSLlrN4kTTTL6v+iKYzAJAqL7i/gSo5AwBJMp5rAAAAAACgAgwAADNRsN0qUBZjACBpWVH9DgCXTuuXkqaq/hyUj/sbqJYxAJCkgp1tAAAAAABA
BRgAAP4/e3ceHXdd73/89Z6ZJLSAitfWjU128aJAqSKg4gLiCi7hQpNUwHuLV8UrP1BKk+gXM2nBi6JyXagKbTJp0eB6rwuKUHHBBVllqRQELGvBsrU0ycy8
f3+0iChLk1ne8515Ps7p0VM9nafnGCbN9zWfTyWMAQBQLXx6Md3K2doPAEZHrSTV/qQB1AQn5gA1csIJ3uHSTtEdmLy2MgMAAAAAAABQfQwAgAqUnQEAUDWm
vaITMHVtpdoPACTJ+bRkWjHwAWpk6we1u6RcdAcm7cFkud0XHQEAAAAAAJoPAwCgAsYDS6AqksQzkvaJ7sCUjWtX3VmPFzJjAJBS/5oc7DygBGogW9be0Q2Y
At7PAAAAAABAjTAAACrzogXd/sLoCCDtijdrd0lbR3dgaly6PUmsXKcXu7kur4Nqmza+nfaIjgCakmtWdAKmhAEAAAAAAACoCQYAQIXMtF90A5B2VubhRZqZ
1+f4f0kMAFKMr3OgNtz42kopBgAAAAAAAKAmGAAAFTI+dQVULsPXUZq51W8AUCrzwCStMtK+0Q1As+ns9KzEFQCpxKANAAAAAADUCAMAoEImTgAAKuXO11Gq
mW6r10s98jz9WVKpXq+H6nFjAABU2x7TtYekLaM7MHnGCQAAAAAAAKBGGAAAFXLpldENQJoliWckvSK6A1OXKdfvBICzz7YxSavr9Xqoqr03fVoZQLWUOEEn
rUoMAAAAAAAAQI0wAAAqN6P3KN8uOgJIq/GbtaekraM7MHXlbP0GAJvcUOfXQ3VstfsW2i06AmgmztUaafXgwoLujo4AAAAAAADNiQEAUAXWptnRDUBaZaWD
ohtQGS/X9x5jc11Tz9dDFbn2j04AmgxfU+l0tWQeHQEAAAAAAJoTAwCgGpwHmMBUOV8/affAwoLdVefXvLrOr4fqOTA6AGgWJ3b6NEn7RHdgCoz3MQAAAAAA
UDsMAIBqML02OgFIMQYA6XZd3V8xx4OTFOPrHaiSrdu0v6T26A5MCe9jAAAAAACgZhgAANXg2vuUTn92dAaQNkmXbytph+gOVMB0fb1fMnubVkraUO/XRVXs
lvT4zOgIoBmUTK+JbsDUOAMAAAAAAABQQwwAgOrItnXo1dERQNqUxOkZTeCGer9gssKKUv2HB6gKmyhzDQBQDWZ8LaVUqW0a72EAAAAAAKB2GAAAVWLiU1jA
ZJV5eJF6maAH8e66JuJ1UTnL8HUPVKqz07OSXhXdgSn5U7LY1kdHAAAAAACA5sUAAKgSl14X3QCkTUY6OLoBlSlNhH2KkeOT08p1UHQCkHZ7TNPLJXH9VDrx
/gUAAAAAAGqKAQBQPfsl83x6dASQFr1H+XYu7RndgYo8NHi+Vke8cNZ5gJJis07pdB5cAhUol/XG6AZM2VXRAQAAAAAAoLkxAACqp2N8HacAAJsrk9OboxtQ
sesl84gXzkwwAEixXK6N0z+ACh0aHYAp4/0LAAAAAADUFAMAoIoyxgNNYBJ4eJFybmHH/ysZtb9KuiPq9VEZMx0S3QCk1YmdPs3EVRppVWYAAAAAAAAAaowB
AFBdh0UHAH3bblEAACAASURBVGnQ2elZN44vTj3XDcEFPERJK2MABEzVlh16naRp0R2YkjULC3ZXdAQAAAAAAGhuDACA6to9meM7RUcAjW63ds2W67nRHaiM
BZ4AsMkfgl8fU7drcozvGB0BpBQDmpRy1xXRDQAAAAAAoPkxAACqrJjhGgDgmRjXZTSFXDZ8APDr4NdHBYoTXAMATIkzAEgrM/0qugEAAAAAADQ/BgBAlZnz
YBPYDO+MDkCFTH9Nlui2yIRcTr+RVI5sQAW4BgCYtKTLt5XpZdEdmJqMM1wDAAAAAAC1xwAAqDI3vTE5xreI7gAaVTLXt5e0T3QHKuS6XDKPTEiW2AOSrots
QEUO4/0SmJxiRodHN2DKSplx/TY6AgAAAAAAND8GAED1bVUs8qlG4KkUy3qXJIvuQGXM9bvohk34NGV6bVUs6Q3REUCauOtd0Q2YsquTUXskOgIAAAAAADQ/
BgBAbbw7OgBoYDy8aAJl1+XRDZJkDABSzZ1PMwObKznGn2PSa6M7MEWmX0UnAAAAAACA1sAAAKiNw5NOb4+OABrNqXP9XyQdGN2BKsg1xgAgywAg1Uw6vLPT
s9EdQBqUinqnpLboDkwNgzUAAAAAAFAvDACA2nhOsV0HR0cAjSZX0uGSctEdqNjdg0N2R3SEJCUFWyXp7ugOTNnz92jX/tERQEocER2AqcsaAwAAAAAAAFAf
DACAGnHTe6IbgIZjXI/RDEz6fXTD3zPpsugGTJ0b1wAAz+TETp/m0qHRHZiyO5Ihuz06AgAAAAAAtAYGAECNmHQExxoDj0t6fCYPL5pD2Rvj+P/HlDlWOdVc
eo/kFt0BNLLpHXqrpC2jOzBlv4oOAAAAAAAArYMBAFA7M3dv1xujI4BGMSEdJe4ubgreYCcAiAFAqpm0U/9crgEAno5J3dENmDo3BgAAAAAAAKB+GAAAtZTR
+6ITgEZhzsOLZtGe0R+iG/7eQ9voD5LGojswdeUy/3wAnkrS6c+V9NboDkxdpsxVNQAAAAAAoH4YAAC15HrXKZ3+7OgMIFrfHN9V0uzoDlTOXbcmw3ZvdMff
O/tsG3PjFIA0M6lz3jznhBDgSZS20JGS2qM7MGUPZO/QldERAAAAAACgdTAAAGprWtsWem90BBDNTHOjG1AdZro8uuFJlfWT6ARUZMbz1uvQ6AigETkn6KTd
RckKK0ZHAAAAAACA1sEAAKg158EnWluSeKbM3cVNw70x7zF2YwCQdhmpK7oBaDS9c3wHSQdEd2DqTLowugEAAAAAALQWBgBA7b0mmeM7RUcAUco36xAz7Rjd
gepw14rohiezsKArJTXU1QSYtMOTLn9WdATQUEzvk2TRGZi6bIaBGgAAAAAAqC8GAEDtWcl0bHQEEKXs+kB0A6pmbftuuiY64smZS/ppdAUqMr1onAIAPCZJ
PGOm46I7UJEbkiG7PToCAAAAAAC0FgYAQB246fgTTvCO6A6g3pIu31bS26M7UB3mujRJrBzd8VTcGQA0AQZDwCYTN+ttknaI7kBF+PQ/AAAAAACoOwYAQH3M
eM5f9Z7oCKDeShn9h6RcdAeqwzP6eXTD02lr04WSPLoDFXl5b5fvHx0BNIKM6/joBlSm7LowugEAAAAAALQeBgBAnbjpQ9ENQD0lB3vOXe+P7kD1mGlFdMPT
SZbY3ZKuje5AxXjoiZaXzPXtXTosugMVGRvP6NLoCAAAAAAA0HoYAAD1c0D/XN8nOgKol4ltdbikF0d3oGoeuPFRXRMd8UyM45ZTz0z/lnT6c6M7gEilso6X
lI3uQAVcvzhz2NZFZwAAAAAAgNbDAACoIy9zCgBah0n/L7oBVXXp6KiVoiOeCQOApjBtol1zoyOAKEmnt7t0XHQHKmS8HwEAAAAAgBgMAID6OvrUY31GdARQ
a/1dfqCkA6I7UD0u/Ty6YXNkcvqFpPXRHajYfyUHey46AohQale3pBdEd6Ay5YwujG4AAAAAAACtiQEAUF/Tc+P6SHQEUHOmU6ITUF0urYhu2BzJEttg0iXR
HaiMmXYsbat3R3cA9ecm00nRFajY6oVDujY6AgAAAAAAtCYGAECduemEUzr92dEdQK2cerTv4dLbojtQVQ/eNKaroyM2m+vb0QmonEsfi24A6q23R293ac/o
DlTsW5J5dAQAAAAAAGhNDACA+nt2W4fmRUcAtZLJ6BTx/tJUTLp0dNRK0R2bq5jV9yQVoztQsf36e/x10RFAPZkzfGkGJn0rugEAAAAAALQuHtAAMU5MjvEt
oiOAaku6fFszzYnuQHW59KPohslYNGT3y9NxZQGenksnRzcA9dI7x18p6TXRHajYPTeO6dfREQAAAAAAoHUxAABivLBU0tzoCKDaiqY+Se3RHaguL+uH0Q2T
ZRk+fdkUXG87tcs5Dh0tIZPR/OgGVM5d30nTqTkAAAAAAKD5MAAAgpTLOvWEE7wjugOolmSO7yTpuOgOVN21g8vstuiIySoV9R1JPIBJP8tm9InoCKDWFnT7
vi4dEd2BymWlC6IbAAAAAABAa2MAAAQx047PekDHR3cA1VLM6JOS2qI7UF1m+kF0w1QsXG73SPpVdAeqwHVkf7e/IjoDqKWs9ClJFt2Bit2fuUM/j44AAAAA
AACtjQEAEMhc/UmXPyu6A6jUqXN9N0lzojtQfeWUDgAkyY1rAJqESfpkdARQK/1dPtult0Z3oCq+m6ywYnQEAAAAAABobQwAgFjPK5pOjI4AKpUta1BSLroD
Vbe27Xb9JjpiyjYOADw6A5Vz6Yj+Lp8d3QHUgksLxaf/m0LZGZ4BAAAAAIB4DACAeCedeqzPiI4ApmrTQ7n3RHegJn6c5k8yDg7ZHZJ+F92BqjDP6BPREUC1
9c71g2R6U3QHquLB9nH9LDoCAAAAAACAAQAQb+vshHqjI4CpcXPp8+KTi03JXD+MbqiUSxdEN6BKXG/v7/IDozOA6nGzss6IrkDV/G8yauPREQAAAAAAAAwA
gMbwof4u3ys6Apis3h51y/Tq6A7URClb1o+jIyrVltMF4hqApuGms5LE+f4VTaG/S0dLOiC6A9Xhpm9GNwAAAAAAAEgMAIBGkSubzoqOACYj6fStzHV6dAdq
5rfJcrsvOqJSyRK7VdLPoztQNbNLq9QdHQFU6sROn+amRdEdqJp71kxL/2gOAIBmMV7klEIAANDaGAAADcKkN/b2eGd0B7C5iu1aIOlF0R2oDZd+EN1QLe5a
Et2A6nHp0x8/zreO7gAqsWWHTpW0fXQHqsOk4cWLbSK6AwAAbGRF5aIbAAAAIjEAABqISZ85uce3jO4Anknf+3xnmU6M7kDtmPSt6IZqGcvoAkkPR3egap7f
Pq6PRUcAU9V7lG8n6aToDlSRayg6AQAAPK4tp47oBgAAgEgMAIBG4tpummtBdAbw9Ny8pC9L2iK6BDVzRb5gK6MjquXMYVvnptHoDlTVyb1zfIfoCGAqLKcz
JU2P7kCVmH43MGLXRmcAAIDHjbnaoxsAAAAiMQAAGoxLJ/d3+V7RHcBT6e/SsSYdEt2BmvpmdEC1ZbgGoNlMU0Zfjo4AJmtBl79F0pHRHagek86LbgAAAE+U
y3ICAAAAaG0MAIDG0+6moXnzvC06BPhHyTH+AjedGd2BmvJcTt+Ijqi2gYL9QlLTnGoAyaS39Pf4UdEdwOY6uce3zJi+GN2BqtowUWq+90wAAFKPEwAAAECL
YwAANKa9ZzyqU6IjgH9UnNAXJW0T3YGa+m2yxG6NjqgFNxWiG1Bd7jo7OdqfF90BbI4tpEWSXhLdgSoyffv0ZbY2OgMAAPwTriwEAAAtjQEA0KDM1b9grr88
ugN4TG+3v0emd0d3oMas+Y7/f0xbWUsklaI7UFXPK2b16egI4Jn09/ir5PpgdAeqzDj+HwCARuTSv0Q3AAAARGIAADSu9kyZqwDQGBYc7c83cWxxCyh7Ew8A
khFbLdcl0R2oumM/0e2HREcATyXp9HYv6+uSstEtqKrVKx/lPQUAgEZk0szoBgAAgEgMAIDG9ornr1cSHYHWliSeyWS1TNLzo1tQc78cHLI7oiNqyU1LohtQ
fWXT1+fPca4nQUMqdigv08uiO1B1542OGqfKAADQgNw1I7oBAAAgEgMAoMG5NP8TPf7m6A60ruJNOlXSG6I7UBfnRwfUWltO35K0JroDVebaLpfRl6IzgH+0
6XSKk6I7UHXFTac6AABahHOVWKo4JwAAAIAWxwAAaHyZsms4OcpfFB2C1tM7x18p0yejO1AXpXJJ346OqLVkiW2QaXF0B2riqN4e74mOAB5z6rE+oywtFX/n
akbfHVxmt0VHAADqx6SJ6AZsPq4AAAAArY4fRgHpMKOY00hnp3N3LOomOcafI9M3JLVFt6D2XLp44XK7J7qjHnIT+pL4AV5TMteXTp3ru0V3AJJbdkJfk/TC
6BJUn2f0+egGAEB9mfP3h5ThQzQAAKClMQAA0uPgPbbQJ6Ij0Bo6Oz07UdQyM+0Y3YL6yJjOjW6ol+R8u1PSt6I7UBNbZcsamTfPGS4hVF+3PiLpndEdqIkr
B4fsl9ERAIA6MxWjEzApjIIBAEBLYwAApIi7+nrn+OHRHWh+u3dokUlvie5A3dyfzeq70RH15M6nN5vYfjPX64zoCLSu3i7fX+L/g83KpM9FNwAA6s85QSxt
Ziad/tzoCAAAgCgMAIB0yVhGy3p7fL/oEDSv3m7vkvSx6A7U1VCyxDZER9TT4Ij9RtJvoztQMyf29/gx0RFoPckx/gIzXSCpI7oFNXFvNqdvRkcAAAJwBUDq
TLRzCgAAAGhdDACA9Jluru/1zvUXR4eg+fTP9X1MWhzdgfqyrL4e3RDBXF+IbkDtuOvLDOZQT/PmeVuxqG9K4nu05vWlVhvMAQA24QqANNo9OgAAACAKAwAg
nV5kZV2QHONbRIegeSRdvq2X9X1J06NbUEeuywaW2nXRGRHu2VKjklZHd6BmtjDXt0491mdEh6A1zFivL0l6TXQHamY8l9M50REAgBhuejS6AZOTkfaMbgAA
AIjCAABIr/2LRZ2XJM7XMSqWdPpzi9KPJW0b3YL6Mulr0Q1RFi+2CXHiRbPbPjuh8+fN87boEDS3vh7/kEn/Ht2BGnJ9I1lid0dnAABiZKSHohswOW46ILoB
AAAgCg8OgXQ7qrhK/xMdgXQ7sdOnFTv0PZleFt2CunskO97adxmX2vQVSRzn3NzeMHO9zpPcokPQnHp7/B1yfS66A7Vl0tnRDQCAOOWyHoxuwKTN5uRMAADQ
qhgAAOn3n31dvjA6Auk0b563bdmhCyQdFN2CECPJqD0SHRFp0Xm2RtJIdAdqrqu/W/noCDSf3rl+kLm+ISkX3YKaunRgxH4fHQEAiGMZBgAp1FEqanZ0BAAA
QAQGAEAzMJ3a2+Mfj85AuiSJZ2au09clvTW6BTHcWvf4/yfIapGkYnQGasulBX3d/l/RHWge/e/zl5nre5KmRbegxjIaiE4AAMSyEgOANHLjww4AAKA1MQAA
moS5Tu/r9uOjO5AOSeKZ4ip9Taae6BaEuWpw2C6PjmgE+aV2s1zLoztQF5/t6/L3Rkcg/ZIu39ZL+qFcz41uQY25LssP2UXRGQCAWFlOAEgld70xugEAACAC
AwCgeZikL/d1+QnRIWhsnZ2eLa7SUknHRrcgkOtL0QkNxTQoqRSdgZrLyDTc1+WHRocgvZKj/EVF00WSto9uQe1lMjotugEAEG+sjQFAGpl0cNLjM6M7AAAA
6o0BANBcTKYv9HX76dEhaEydnZ7dvUNLJHVHtyDUmnXjKkRHNJJ8wVbK9I3oDtTFFjJ9v7fH3xEdgvRJjvEXlHL6qaTdo1tQF7/91LBdGB0BAIjX8YgelOTR
HZi0bEl6d3QEAABAvTEAAJrTKf09vig6Ao0l6fT23dv1TfHwH9KXzhq1R6MjGlBeUjk6AnXRYa4LGAFgMnqP8u0mivqFS3tGt6BOTJ+KTgAANIZk1MZlWhvd
gckrS0dGNwAAANQbAwCgSblrfl+X/0+SOF/nUHKMP6fYoR/JWL5DG3LG8f9PJj9sN0i6ILoDddNurgv6uv2d0SFofMlc395yusSkXaJbUDdX5If1o+gIAEAD
cd0ZnYDJM9drF3T7C6M7AAAA6okHg0AzM31oYpX+L+nyZ0WnIE5fj7+kWNSvJb0hugUNwDScDNu90RmNylx5cbRnK2mX9M3eLn9XdAga16lzfbeJkn4uaefo
FtSPmxLJeD8AAPyNS3dFN2BKslnXB6MjAAAA6okBANDkTHpL0fTL3jm+Q3QL6q93jr9SrsskvTS6BQ3BS2V9LjqikQ2M2LVyfSe6A3XVYabRvi4/IToEjae3
y/fPlvVLM+0Y3YK6unJwWP8XHQEAaCwmTgBIKzd9KOn0raI7AAAA6oUBANAa9rKMftPf46+KDkH99Hb7eyyjSyQ9P7oFjcGlHy8aseujOxpd2TUgTgFoNVmZ
vtDf5Z/n6hw8prfb32OmiyXNiG5BfXlZp/HpfwDAP+EKgDTbZqJd/x4dAQAAUC/8gBNoHS9w1yX93T43OgS1lRzsub4eP9OkUUnTo3vQOCyjz0Y3pMHCZXaV
Sd+N7kD9uekjxVVafsIJ3hHdgli9Pf7xTe+j06JbUHdXDC7T96MjAAANiSsAUsxMJyad3h7dAQAAUA8MAIDWMs2lpX1dPsTRZ82pd66/uLitLpHrJEkW3YOG
cm1+SD+LjkgLl06VNBHdgRBHPnutLkqO8RdEh6D+kmN8i95u/6q5zhDvo63J9DE+/Q8AeDJunACQcttPdOjk6AgAAIB6YAAAtCJTT7FDl/d3+yuiU1A9fd1+
sJV1uaSDolvQeNz1GR5obL58wVa6dE50B8IcVCzq6r4ef0N0COqn9yjfrljUChPHw7aw7+eH7eLoCABAY3Lpz9ENqIxJfckc3ym6AwAAoNYYAACta3eXLuvr
9uOjQ1CZ5Bjfoq/bT5d0kSQ+sYonc1vbuJZHR6RNW0mnSXowugNhZsp1YV+3nyI5nwRvcn09/lZr01WSXhXdgjBFy2pBdAQAoHEV23VTdAMqNq2Y0RejIwAA
AGqNAQDQ2qZJ+kpvl/+4d47vEB2Dyevv8VcVi7pC0imSstE9aFCuwWTUxqMz0iZZbvdJWhTdgVA5Saf3d+k7p3T6s6NjUAtufd1+ilz/K9dzo2sQyHXOwFK7
LjoDANC4Pn2uPSzp7ugOVOyw/i7vjo4AAACoJQYAAGSmN1tG1/d1+ymdnc5D5BR47FP/7vqVpJdG96Ch3ZYb19LoiLTKjeksl26J7kAsNx2ea9dVfd1+cHQL
qieZ4zv1desSSaeLvxe1uofLZQ1ERwAAUoFTAJqAm77a3+WzozsAAABqhR90AXjMdEmn796hS/t6nAfKDayv2w/mU//YXCbl+fT/1CWjNp5x9Ud3IJ6ZdpR0
cW+3n3Nyj28Z3YNKuPX3+LxiRtdIel10DRrC4MLldk90BACg8bkxAGgSW7jpgqTHZ0aHAAAA1AIDAAD/6AC5ru7t9nNOPdZnRMfgcUmXb9vX5UOSLhaf+sfm
uS07pqHoiLQbGNFyuS6L7kBDMJPmbeG6uneuHxQdg8lLjvEde3v0M3edI4khByRpdW66zo6OAACkRJkBQBPZvugaTeb59OgQAACAamMAAODJtJk0LzuhlX3d
fsoJJ3hHdFArS+b59L5uP6VoukGmHkkW3YTUOI1P/1eDubvmR1egoexsZV3S3+3//fHjfOvoGDyzefO8ra/LTyoWda25Xh/dg8bh0vxksa2P7gAApINl9Kfo
BlTVa4vr9aOky58VHQIAAFBNDAAAPJ1tJJ3+nLW6pq/bj5CcB891lHR6e1+X/0fxUd2ojfcTbxXdhFS5Obdaw9ERzWJwmV0q6bvRHWgoOZdObh/Xyv4en5ck
zvfVDeoTXf7Gmet0pUxnivdSPNGVbbtoeXQEACA9cq5rohtQda8tZnRxcrQ/LzoEAACgWvhBJYBn5NJukr7T162r+7t9bmenc+98Dc2b52393T53okPXybRY
ru2im5A+7hpIVlgxuqOZ5Mo6SdKj0R1oOC901znFVfpF/xyfFR2Dx/W9z3fu6/bvlU0XyfSy6B40nLK7PpgkVo4OAQCkR1LQzZIeiu5AlblmFTNacerRvkd0
CgAAQDUwAAAwGXu5tHSPLfTH3i5/37x53hYd1ExOOME7+rv8gzMf1c0uLTVpl+gmpNZNbXdoJDqi2STL7BaZBqI70LAO8Ix+19vjX+/r8ZdEx7SypMdn9vX4
mSrpOknvjO5BY3LpK4Mj9pvoDgBA2phLujq6AjVgelk2qyv6uv2/olMAAAAqxQAAwKS5aw8zLZmxTn/q6/aPcUxaZXrn+A79Pb7o2Wv1Fzd9kU/8o1Lm+hSf
/q+N3F/03+IHfnhqGXMdJ9fKvi4fSrqdIVcdJUf78/q6PSm6bpLrJEkd0U1oWHe35dQbHQEASCnTVdEJqJlpkj7X3+0X8LMuAACQZgwAAEyZmXaU9OliVnf0
d/s3++b6myS36K606J3rB/V3+zcto1Xumi9pRnQTmsKV2V21LDqiWSUrrGim4yVxZDSeTptMPUXp+r4uH+p7n+8cHdTM/vbgP6ubJX1S0rOim9DYXPpwssQe
iO4AAKSU68roBNSWS+8pZvXnvm4//ePH+dbRPQAAAJPFg7oG0t/jN7iLu6aQaiZd765zc1mNJkN2e3RPozn1aN8jm9VRkuZI2jW6B83Hy3rd4DK7NLqj2fV2
+zkmzYvuQGpMmPRdz2hxfsguio5pFv1zfZ9yWR8wqVvS9OgepINLPxos2FujO9Kqt8vPM9Mx0R3YPLmctmHsAlTfgjm+dybDCKCF3ClXkhvX0mTUxqNj6iFJ
PFP6s15aLmo/k2Yro9kq6/v5ERuMbgMAAJsnFx0AoLm4tKdMZxbLOrO/2693aTQnFZKCrYpui9J7lG9nOb1bUqekA6N70LxMGs3z8L8uimP6eFuH3iHphdEt
SIU2lzpVVmdft19ppq9kp6mQLLb10WFpk3R6+8QWOtzKmudlvYk1MyZpvZk+FB0BAEi39gldX+zQBklbRLegLl4k0+Jih/J93b5UZX01v8xuio6qHrdkjl4y
YZqdMe3n0uziKu0raWt77Jttl9x0f2QlAACYHH5m1kA4AQBNzCX9VtIPLaOLsrfr9818P/m8ed42c70OlOtQZXSoXPuKf96i9sZyZe2ZLLNbokNaRX+Xz3HT
SHQHUus+mZaWXcsWFuyK6JhGt2CuvzzrOtpdx0h6QXQP0smlkwYL9tnojjTjBIB04QQAoHb6un2FpNdFdyCEu2mFlbU8l9WFaTn9MjnYc2Pba6dMSS+zjPaQ
a0+ZXqqNP4vecjP+iDX5gs2sdScAAKgOHkg1EAYAaCEPSrpEposkXZwf1o2SeXTUVHV2enaPdu0p0+skHerS6yVtFd2FlnNGvmDzoyNaTV+3/0ASR0mjIu66
1UzfkHRevmAro3saRe8c38EyOkLSXEn7Rvcg9a7JrdasZh6h1gMDgHRhAADUTn+XD7ipL7oDDeEGM11YKusn3q7LF51na6JCksQzE7fohZmSdiybts+Y9pDr
pS69VNJuktor+fNzOb0kWWK3ViUWAADUFFcAAIjwbElHyHWEJPV162HJrzHXH2T6g7L6w8BSXd+oo4DkKH/RRJtmmWuWTLPkOtClbaK70NLunRjTouiIlpTV
R1TS6yVNi05BeplpR0mnSDqlr8f/4K5vZ8q6MLubrkwSKwfn1U2SeGZ8lfbOmN4s17skzY5uQtMouen9PPwHAFSLS7+IbkDDeKm7XpoxfVQTUl+33+WuazLS
1ZKulem2rHSXpuvOSq8A+/hxvnX2Ub04m9H2Ztrepe0l7bDp1/bFVdrWpDa3jZ/68yr/VG2iqFmSbq3unwoAAGqBAQCARrC1pAPddKAkqST1desByW+StMpM
N5WlVSrrpraMbkmG7d7a5rgtOFozLaOXZEy7ybWrZ7SrXLtK2rUobf23aUJDThTQclx9Z4zag9EZrSi/1G7u6/ZPSvp0dAuahGuWSbM8o8HiKt3b1+0/NdeP
sxn9pPbvf/W34Gh/vuV0qLneXFylQzLSTN5bUW0mnZUftsujOwAAzSM3rl8XO1QUP1vFP3uhmV7o0psf+42iJK2X+rr9IUl3SLpfrg0yjZu0zqWiSw9Lkpm2
MlebbzyWf0tJ//K3X+NqV3bjnxnxLbNtHOh+K+ClAQDAJPFNKoBG9Rxt/IvFbPdN95XYxr8R9XV7UdIaSfdt+td7ZLpPrvUyPShX2V1jmYzWS1JZWmtlPccy
snJZ083UIVdOpq3NNc0zep5cL5A0U9IMSc+TNv6Vyje9Lg8j0MCuXjmuc6MjWlluF32muEpvl/Ta6BY0nZmSutzUVXR5X5dfL9PvJP2+LP32vum6dvFim4iO
3FxJp7eX2vUKSbPL0uyM6ZUuvVTOtWSoqWse2IYjmgEA1ZWM2iN93X6VpP2iW5Aqz9r0628X8z7246a/fUPsDfwjKNes6AQAALB5GAAASKOcpBdu+rXRP3wi
3+zxo84eGw+4b/z9x39Tch7uI+1M/2901ErRGa0sSazcO8fnWkZXa+MVJ0AtmEwvk/QyScdmJM1crw19XX6lpCvMdOOmE3P+tHKDbo/850JysOe0rXYcd+2a
Me0maXdJ+xalvSV1bPwfw9sv6mLMXN1nn21j0SEAgOZj0qXOAACtxDRr40/SGvPKTgAA8DgGAAAApJVpWX7YLo7OgDS4zG7r7fETzDUU3YKWsoVMr5b0atfj
w7fdOzTW3+03u/Qnl1bLtcZMa9x1t7JaY2WtyY1pzYPSo2eN2qOb+2In9/iWWxU1rZjTDC9phplmKqPnyzXDpRlm2l6uXYvSTpLaMnyuH8FcWpAfsWujOwAA
zclMP3HX/4vuAOpom7452iW/TDdFe5FCnwAAIABJREFUhwAAgKfHAAAAgDQy/TUnnRidgccNDttwf7e/w6XO6Ba0vA6X9pS052On4EibTsEpb/z3xY6NF4r2
dbsklSQ9JEnuelCmspna5Npq05+3jSTJpWJ2479aZtN/8ven7fA5IDSWi9t20eeiIwAAzWvtc7Ti2Wv1iPS375mApucZ7ScxAAAAoNFlnvm/AgAAGo1JJyXD
dm90B54om9M8mf4S3QFMUlYbH/JvY6YdTdpJru0e+73YNGBKHshldGySWDk6BADQvDZdMcOJbGgpZpoV3QAAAJ4ZAwAAANJnxcCwlkZH4J8lS+wBmY4Tn4UG
gDBm+s9kyG6P7gAAND8z/SC6Aagr1+zoBAAA8MwYAAAAkC5jkj4gGQ+YG1R+yC4y19nRHQDQogoDw3Z+dAQAoDVkJ/R/YvyL1rJvZ6dnoyMAAMDTYwAATM3D
Jo0+4ZfpxugoAM3PXUm+YCujO/D0HniuPi7p2ugOAGgxq4tlfSQ6AgDQOpLz7U5J10R3AHW01S7t2j06AgAAPL1cdACQRma6Y2DYjvz73+vv8r1kukoMawDU
zrVrttRnoiPwzM4+28YWzPXuTFmXSZoe3QMALWDCMzr69IKtjQ4BALSc70h6RXQEUC85036Sro/uAAAAT40HlUCVDIzYtSZ9K7oDQNMqW0bHL15sE9Eh2DwL
h+wal/49ugMAWoGbTh4csl9GdwAAWk9OGoluAOrKNSs6AQAAPD0GAEAVFUv6hKRSdAeApvT5gSG7LDoCkzNYsOVyfTG6AwCa3PLBYftCdAQAoDUlBVsl6fLo
DqBeXJod3QAAAJ4eAwCgihYttxvF8htAlZl0/box9UZ3YGru3VInSuJTqQBQG9duMP1HdAQAoLW5tDy6Aagb0z7z5nlbdAYAAHhqDACAKsvl9ElJ49EdAJrG
mKQ5Z43ao9EhmJrFi20il1OnpLuiWwCgyTxcKunIM4dtXXQIAKC1bRoAcCIkWsUWz1+vPaMjAADAU2MAAFRZssRudde50R0AmoO75g8U7OroDlQmWWJ3Z8rq
klSMbgGAJuEyHbPpBC4AAEItLNhdkn4e3QHUi5v2i24AAABPjQEAUANtJQ1IeiS6A0Dq/WRwRJ+PjkB1fGqZXeLGVQ4AUA3mGswP27ejOwAAeIy7hqIbgHrx
MgMAAAAaGQMAoAaS8+1OuU6P7gCQaveVpWMk8+gQVM/gsP7bpNHoDgBIM5d+duO4kugOAAD+3vpxfVPS/dEdQD0YJwAAANDQGAAANZJr02fcdWt0B4B0ctMH
Nx0jiaZinnX9u6QboksAIKX+3FbSUaOjxj3LAICGctaoPWrS0ugOoE5efsIJ3hEdAQAAnhwDAKBGkiW2IWM6JboDQCqdMzhsfEq8SSUj9lAup7dKuie6BQBS
5kFzHZ4st/uiQwAAeDKe1ZcklaM7gDpof9YD2is6AgAAPDkGAEANDRQ0KumX0R0AUmXlBtNJ0RGorWSJ3eqmt0taF90CACkxkXG9Z2DEro0OAQDgqeSX2s1y
XRzdAdRDRlwDAABAo2IAANSUuWX0EbH+BrB51pVN7z1z2Hgo3AIGh+3ysvRvkjjGGgCenrvp/Z8asZ9FhwAA8Iwy+nJ0AlAP7gwAAABoVAwAgBobGLIr3TUU
3QGg4bm73r9w2P4YHYL6WViwH0j6UHQHADQyl/oGh204ugMAgM2xcoO+J+mm6A6gDhgAAADQoBgAAHXQVtbHJK2J7gDQ0M4cHLFvREeg/vIFO8dMn4vuAIAG
9fXBgi2MjgAAYHONjlpJ0meiO4A6+Ndknk+PjgAAAP+MAQBQB8lyu89dH4vuANCwLs6t1oLoCMTJ7qyT5Pp2dAcANJgf51brA9ERAABM1oPbaImkO6I7gBrL
ljboFdERAADgnzEAAOpkcMSWuvTT6A4ADef2UpuOSlZYMToEcZLEyuvG1S3XZdEtANAg/jgxxvsjACCdzj7bxuQ6K7oDqDUvcQ0AAACNiAEAUEdtOc2TtC66
A0DD2GCu9y46z7giBDpr1B7NZXSES6uiWwAg2O2e0WFnjNqD0SEAAEzVhoy+Ium+6A6gpowBAAAAjYgBAFBHyRK7VdJAdAeAxmCuDw2M2O+jO9A4kmG7V0W9
QdKfo1sAIMg9pZLePDhkHJsMAEi1M4dtnZs+H90B1JKJAQAAAI2IAQBQZ7nV+oykq6I7AARzfXFgxM6NzkDjGTzf/uJlvV7SbdEtAFBn95Zcb1i03G6MDgEA
oBrGpLMk3RXdAdSKS3t8/DjfOroDAAA8EQMAoM6SFVZ0039I4j5ToHX9MHeHPhodgcY1uMxuU1mHiB8WAmgd95VNb1w0YtdHhwAAUC1nDts6SadFdwA1lGnb
oH2iIwAAwBMxAAACDA7b5e5cBQC0qMtzY/q3ZIUxAsLTyi+zmyS9XtI90S0AUGMPWFmHLRy2P0aHAABQbSvH9DW5rovuAGrFTLOjGwAAwBMxAACCtO2qvKSf
R3cAqKs/l0t6ezJqj0SHIB3yBVtp0psl3R/dAgA18qC5Dh1YZn+IDgEAoBZGR60k04LoDqBmTLOiEwAAwBMxAACCJImVvageSWujWwDUxf2S3rJwufFpbkzK
QMGutowOEe8XAJrPOpPeMTBiv48OAQCglvIF+76kS6M7gBrZLzoAAAA8EQMAINDg+fYXc30kugNAzT3q0jvzBVsZHYJ0GhiyKy2jt0l6OLoFAKpkvaS3DxTs
F9EhAADUg7k+LGkiugOogV2STn9udAQAAHgcAwAg2MCIFSSNRHcAqJmSu7oGC/br6BCk28CQXeZlvV3SQ9EtAFChhyS9LV+wFdEhAADUy8CIXSvpc9EdQA1Y
uV37REcAAIDHMQAAGsDEmD7krlujOwBUn0kfHRyx70R3oDkMLrNLy9LrJd0b3QIAU2L6q7vezMN/AEAryk1X4tIt0R1AtZWk2dENAADgcQwAgAZwxqg9mJG6
xVFwQLP5xEDB/ic6As1lYcGuyJX1akk3R7cAwCTdLtcBgyP2m+gQAAAiJIttvUkfiu4Aqs1Ms6IbAADA4xgAAA1iYMR+JddJ0R0Aqua0fMEGoiPQnJJldktZ
eo2ka6NbAGBzmOlGL+qgfMFWRrcAABApX7AfmzQa3QFUk7v2i24AAACPYwAANJD8iJ0t6evRHQAqY9KZ+YIl0R1obgsLdlexrNfJdVl0CwA8g8uLOb128Hz7
S3QIAACNoFTSCeJaLzQRM+146rE+I7oDAABsxAAAaDC5nD4s0++iOwBMjUmfHSjYx6I70BpOX2ZrN2R0iKSfRLcAwFNYkXO9cdF5tiY6BACARrFwud0j6X2S
PLoFqBYb5xQAAAAaBQMAoMEkS2xD2XWEpLuiWwBMjpk+N1AwrvJAXZ05bOtyY3oHx4gCaDTm+l4up7ckI/ZQdAsAAI0mX7Afu/Tl6A6gWjLGAAAAgEbBAABo
QAsLdpdL75U0Ht0CYLN9fmDYToyOQGtKRm38xjEdLemc6BYAkCR3feXGcb0nWWIbolsAAGhUbTmdJOna6A6gGsw1K7oBAABsxAAAaFCDBfu1XCdHdwDYDKav
5gvi4T9CjY5aKV+wD5jpeEkT0T0AWlZJ0vzBEfvP0VErRccAANDIkiW2oVzWXElj0S1ApZwTAAAAaBgMAIAGlh+xs910bnQHgKdm0mfzwzpeMu5uREMYGLbF
cr1d0gPRLQBazlpldFi+YGdEhwAAkBYLl9lVZvpAdAdQBS9OjvIXRUcAAAAGAEDDWzNNH3DXhdEdAP6JSzptoGAn8fAfjSY/Yj/JSbPNdGN0C4CWcVOppAPy
Q3ZRdAgAAGkzMGxLXFoc3QFUqpjjFAAAABoBAwCgwS1ebBMTHeqUdFV0C4C/KZk0L1+wJDoEeCpJwVZNlHSAXDyMA1BrP8nl9MpFy43REQAAU7Rmuj4s6RfR
HUAlzDQrugEAADAAAFLh0+faw7mi3ibp9ugWAFpflg4fKNjXokOAZ3L6Mlu7clyHSeI4bgA14dLi3Gq9LVliXDsCAEAFFi+2iVxOR0paHd0CTJU7JwAAANAI
GAAAKZGcb3eqrDdJuie6BWhha8116MKC/SA6BNhco6NWyhdsvlzzJE1E9wBoGuPmev9gwY5PVlgxOgYAgGaQLLG73dUp6dHoFmCKGAAAANAAGAAAKZJfZjeV
MzpU0troFqAF3VnO6OCBEftVdAgwFfkR+6qZDpF0Z3QLgJQz/cWl1w+M2LnRKQAANJvBEfuNm/5NEgM7pNHM3jm+Q3QEAACtjgEAkDILh+waz+idktZHtwAt
5I9e1P4Lh+ya6BCgEgPD9vNcSa8wiVMsAEzV90umfQYL9uvoEAAAmtXgsP2vm46T5NEtwKRlOAUAAIBoDACAFBocsl/K9S5xJBxQc+b63ni7Dhg83/4S3QJU
Q7Lc7hso6B2SPippPLoHQGpMSJqfL+iIRUN2f3QMAADNbnDYhiV9MroDmCxzzYpuAACg1TEAAFIqP2I/yUiHixEAUCsu6Yzsrnr3p8+1h6NjgOoyzxfs8+Y6
yKVbomsANDZ33equ1+YLdoZkfBIRAIA6yRdsQNLnozuASZodHQAAQKtjAACk2KcK9lMv6zBJ66JbgCazTq4j8wWbnyRWjo4BamVgxH7f5tpHpm9EtwBoTCZ9
q61N+wyO2G+iWwAAaEX5gk506UvRHcBmM82S3KIzAABoZQwAgJQbXGaXKqMjxAgAqJY/lzM6ID9iF0SHAPWQjNhD+WE7yqT3SVof3QOgYWyQ9NGBgr03WWIP
RMcAANC6zAcL+rBL/xNdAmymbZJu7RwdAQBAK2MAADSB/JBdZK7XS+I+VqAyv8iZ9l84ZNdEhwD1NlCwIcvoIEk3RLcACHeNZbVfvmAcOQwAQEMwHyzoI+b6
QnQJsDlKpv2iGwAAaGUMAIAmMTBivy9n9AZJd0e3AGlkri/kVusNybDdG90CRBkYsivvna5XSJovaSK6B0DdTUg6Izem2QNL7broGAAA8PfMB0b0UTN9LroE
eEauWdEJAAC0MgYAQBNZOGTXKKuDXLolugVIkfvd9e6BEfuvZIUVo2OAaIsX20S+YGeYNFvSFdE9AOrm6rK0f75g85NRG4+OAQAAT8Z8YNhOlHSaJI+uAZ6K
b/z7JAAACMIAAGgy+aV2czmjV0r6ZXQLkAIrcq69B0fsO9EhQKMZKNjV907X/tp4GgAPA4HmtUHSafdO1+yFBWP0AwBACuQLlrjrWPF9OhrXrCRxnj0AABCE
N2GgCS0asvtzOR0i6fzoFqBBFSWdtnJMb0pGbHV0DNCoHjsNoGyaJeny6B4AVea6TKZ98wVLFi82rv0AACBFBkdsqUxvkfRAdAvwJLYq3qzdoyMAAGhVDACA
JpUssQ35guZo47FwAB53m7kOzhcsGR21UnQMkAYLh+2PudV6tTaeBjAW3QOgYo9Kmr9yXK/JD9sN0TEAAGBq8sN2sWV1kKTboluAf+TSftENAAC0KgYAQFMz
zxcsMVePNv6gF2hpJo0Wy9pnYMR+Fd0CpE2ywor5gp1Rcu0r6dLoHgBT464LldVe+YKdwRAOAID0G1hq15WlV4vv0dFgMmUGAAAARGEAALSAgRErmOn1ku6I
bgGC3GeuroGCHXn6MlsbHQOk2aIRuz5fsNe56Z3uujW6B8DmcWmVm44cHLHD8kvt5ugeAABQPQsLdldutd4o6QxJHt0DSJIbAwAAAKIwAABaxMCw/bbUpn3c
dEl0C1BPJo2W2rTnwIgti24BmsngsP1v25Z6mTZeNcMpM0DjWifptLac9hocttHoGAAAUBubTuyaL+kISQ9E9wCS9k4O9lx0BAAArYgBANBCFp1na9ZM05tl
+oxYhKP53VZ2vXWgYEcuOs/WRMcAzShZbOvzBUtyrt3kGo7uAfAEbtJoLqM98wVLkiW2IToIAADUXr5g35e0v6Q/Rreg5U0f3157RkcAANCKGAAALWbxYpvI
D9vJyuhQSXdH9wA1UHZp8Xi79lo4Yj+KjgFaQTJiq/MjNjdT1hskXRPdA0BXmOs1AwU7Mhmy26NjAABAfeULtjKX02xtvBKgFN2D1pUtcQ0AAAARGAAALSo/
ZBeVS9rbpZ9GtwBV9Ed3HThYsOM/fa49HB0DtJpPLbNLcqs1S66PSFob3QO0oLslHZfbRbMHRuxX0TEAACBOssQ25As236XXurQqugetyY0BAAAAERgAAC1s
4XK7509jeotMCySNR/cAFXhEpgX3Tte+gyP2m+gYoJUlK6yYH7Gzx9u1g6T54v5RoB7ul3RazrV7vmDnJYmVo4MAAEBjGCzYryfata9Li8V1kKg/BgAAAARg
AAC0uNFRK+WHbZFlta+kK6J7gEkqyzVclnbLD9uixYttIjoIwEafPtcezhfsjNyYdpZ0mqSHopuAJvSwpDMmxrRzvmBJMmJ8nQEAgH/y6XPt4cGCHV92vc2l
W6J70FJennR6e3QEAACthgEAAEnSwFK7LjemV8s0KKkY3QM8I9dF5Yz2yY/Y3IUFuys6B8CTS0btr/mCJbmSdtbGO0gfjW4CmsAjks4olrVDvmDzzxi1B6OD
AABA41s4Yj9aP6Z/1caB7oboHrSEjlKb9oqOAACg1TAAAPA3yaiN54etzzYez8Ux6mhIJv3JTUfmR+yQhUN2TXQPgM2TLLf78gWbnzPtqI1DAH7gCEzeenN9
oVzSLvmCzT99ma2NDgIAAOly1qg9mi9Yoqz+VdIPo3vQ/DzDNQAAANQbAwAA/2SgYFfndtGBZjpeHNmMRmH6q6T52THtNThso9E5AKYmGbZ78wWb72XtIenr
kri6A3hmj5rpc+WSdvr/7d15sJ1lYcfx33PuuQEDAqEVFxCVxULSRUXr0kW00M64jTN6qxKD1KrVGWl1RjsgUI9NgOo4gxarMxmrgRtCx6t/KEzdxw3ULlHE
sogCsigjZmGRbPfe8/SPHBvqAkSSvPc+9/OZeSckIZlfMvnj3HO+7/OuvKT83XmXlp90PQgAmN9WXVRuXLW2vLAmL6/JD7reQ7tqBAAAsK8JAIBfaTAow5WT
ZXXtZWlJfNhKd0o21Zp3Tm/LUavWlncPpsqOricBD9+568otq9aW1/X7OTLJu0aRD/D/3ZnkXf3ZHLlysrzVB/8AwJ527tryiZ8uztLRTSAer8ceVwQAALDP
la4HsMs5K+p1tea4rnfw4ErJ9Ssny/Fd79iXzllRn1lr3pfkWV1vYcHYmOQD/X7eN1hT7up6DLB3DSbqgbP755Qkb/V6iIWuJDfU5IP3bc/qC6bK1q73wM+d
tbx+tJSc1vUOHpp+P0u8jgZ2x+ANdfHMlpye5Iwkh3S9h2bM3Lc9B3ldCwD7Tr/rAcD8sHKy/EdSn3PWiry81Lw3yZFdb6JZP03ywentueDdU+XurscA+8Zg
qvwsyerBoH54+sa8sAzztyk5qetdsI9dWUvevWoylyeldj0GAFhYBqvLliTvPvPU+uGxYd6e5E1JDup4FvNff/Gi/EGSb3Y9BAAWCo8AAHZDqedOlqn+9ixL
Mkjiw1n2pDtqzVv7i/PEVWvLwIf/sDANBmV47mS5bNUl5eRhckJqJpPMdL0L9qIdqZksNb+/am3543Mny2U+/AcAunT+xWXjqrXljB2LckSStyT5UdebmN9K
8oyuNwDAQuIEAGC3je7SfNdgol44u3/eXmtOT3JA17uYp2quKb18YGwsawZryrau5wBzx3lry7eSnHrWKfWcMpbXp+Y1SY7oehfsId+vyZo6m38979Lyk67H
AAD8ovd8pNyb5P2Difqh2f3yypq8I8nvdL2LeajkhK4nAMBCIgAAfmODqbIpyZmDFfWCmZozkvxNksUdz2J+mCnJJ8sw//KP68qXuh4DzG3nriu3JDl7MKj/
MHNTnp/ZnJqSlyd5RNfbYDdtK8lltZfVqy7OF93pDwDMB4OpsiPJxRMT9ZInL8pLSskbk5wUp8vyUNU8vesJALCQlK4HsMs5K+p1tea4rnfw4ErJ9Ssny/Fd
75hrBq+qvz0zljcneXOS3+p6D3PSnUk+Wof50OgDPYDfyOC0esjsbP6y1rwxyVO73gMPqGR9aib72zM5CihhXjpref1oKTmt6x08NP1+lgzWlLu63gG06ezX
1KMzm9cn+askh3W9hzlvuGNRDhmdKgEA7GVOAAD2mMGlZUOSwemn1/MP2ZxX1OTsJMd2vYs5oGR9SVb/bFsmL5gqW7ueA8x/ow80VidZfc5r6rI6mxVJXhcB
GnNFyaZa8/Fe8sGVk+U7Xc8BANiTVl1Ubkxyxumn13cesikvG5a8tiQnJhnreBpzU2+/HXlKkq91PQQAFgIBALDHXXhh2Z7k4sGJdd3M4XlpSt6U5Hlx6shC
c3upWTc7lkvOu7hc3fUYoF0rLyrXJDnjrRP1XQfulxcneXlNXpDkgI6nsdCUbKrDfKokn7hzcT67enWZ7noSAMDeNHoPaF2Sde94dX1sqXlFKTklyTM6nsbc
MEyyPiWfG87m1q7HAMBCIQAA9prBl8tMko8n+fjZp9Rj08tfx92Zrbs7NZ+qvUyN35ZPj/4NAOwToxNGPpbkY4PT6v7Tszm5DDORkpckObjjebRrY2r+vfYy
Nb4tnx09IxcAYME5b225I8n7krxv9D7QKUlekcRjNBeWW5N8viSfm+nli+dfXDZ2PQgAFhp3484h56yo19Wa47rewYMrJdevnCy+ePkNDN5QF0/fl4lScmp2
Hg3X63gSD9+OUvPpmqztj+fywZqyretBAPc3MVHHnvyIPLs3m4la8ookj+56E/PeT1PzmdrL1E8fkc+405+F4qzl9aOl5LSud/DQ9PtZMnpkDkCnBq+ux8yU
vDg1L0ryJ0nGu97EHlSyqdRcWWs+PzvM58+/tFzf9SQAWOgEAHOIAGD+EADsGYPl9YiZkuWpWZGSZV3vYbfcW5LPpeTysW351GCqbOp6EMBDMTix9odH5HnD
5GUpeUFqHt/1JuaHktyQ5PJh8onxY/LNwaAMu94E+5oAYH4RAABz0eC0esj0dP6ilLwoyckR585H30vy9ZRcmeTrqyZzfVJq16MAgF0EAHOIAGD+EADseeec
Wp9aa16WYV4qBpizbkxyeXq5vL81X3XEMdCCwSn1qNmxnJSak+rONyAP6XoTc8aGknwpJV8YG8vnBmvKD7seBADQmjOX16VjJc/NzlMinxtBwFxzb5KrSs03
6s4P/Hck+XTHmwCYP769am15WtcjFiIBwBwiAJg/BAB719kr6pNS85IkE0meHY8J6MpsSq5KzeVlmMtWrivrux4EsDdNTNSx48bzlNrbGQSk5E+TLOp6F/vM
ttRckZIvlGG+MPbkfNtd/gAA+9aZy+vSfnJiLXlmSZ5ek+PifaF95faSfKeWXJVhruqXXJVjctP9XxOftbw+q5R8o8uRAMwrAoCOCADmEAHA/CEA2Hfe8ar6
6LFe/myYnFxKTk5yeNebGrYtyX+Wmq+WXq7YNp6vv+cj5d6uRwF0ZbC8HjRd87xScnJK/jjJ7yYZ63oXe8z2JN9O8rVe8vl7t+eKC6bK1q5HAQCwy9+/tj5y
v+k8rQ7z9JQ8PckzkjwpooCH487sPMb/htRcl7F8Zzb59vkXl40P9gsFAADsJgFAR/pdDwB4IOddWn6SZN3oypnL69JeLyf1hnl+LXl2ksM6HTi/3Z3kypRc
UUu+ds/B+a8LLyzbux4FMFcMLin3JPnk6MrbVtQD9it5ahnmhNScMIoCntTpSHbHHSlZn5orai9Xjvfy34M1ZVvXowAA+PVGNyZ8ZXQlSQZvqIt3bMlxYzVL
a7I0JccnWZbkqAh2f+7uJDcnuaHU3JDke8OaG8YX5YbBmnJXx9sAgL1MAADMK+dfUq5Ncm2Sf06Ss19Tj67DPCc1zyrJc5L8Xnyx96tsTvKdUnN17eXq4WzW
f386352aKrNdDwOYL947We5LcsXoSpIMXlkfNz2eE0rNCan5o5Q8J8nizkbyc/cmubrUrB/2csV48pXBZLmz61EAADx8g9VlS5Jvja7/c/rpdb+D78pRqXlC
kiek5gnpjb5NnpjksWnj5IB7S8mP6jC31+T2Xi+3pua2mtxexnLb9rHc6kRHAFjYBADAvLbqonJjkhuTTCbJYKIuml2cYzObE0YV+LLU/GEWzkkBszW5pZRc
m5r1teSaXi/Xrrwo1yaldj0OoDWDfys/TvLjJJclyeDE2p89PMen5PiULKs1S0uytCbHJhnvdGybtia5PiXX1ZprUnNdqfmf/pNz4/2fVQoAQPtGpxpeN7p+
yeDE2t9xRB6VXh7Vm81jSnJY7eVRJTms1jy61BxakwPSy5LUHJjkgNG1ZC/MvSfJfUm2pOSu1NxXk/t6yc9qsiHJhlqyoTfMhppsKCU/Gfay4Z6Ds8HpjQDA
gxEAAE0ZTJUdSa4ZXbt+/NR65HA2xw5LjklydGqOTsnRSY7Jzi/m5pM7U/LDJDeXnce53VyH+WFqbu5P55bR3wEAHRh8ucwk+e7o2vXjJ9Z+Hpcjp8eyrNQs
Tc2y9LI0NcfHiQEPxY6S/CDJNTW59ueB2/Vbcr3TbAAAeChGr9XvGF1X79avnagHbhvPeK9m0aKy632k7TWL+uWX31eq47mrP51dN2LU3LOtZHa4f2bcnQ8A
7G0CAGBBGFxcbk1ya5Iv/tLPraiHzQ7z6NnkiJIclpLDS8ljUvPYJI9KclBNDi4lh6Tm4Oz5RwxsS7IxycZasrFXR3V3zcZhsjG9bCzJxmFy647k5tER1ADM
I6M3G28aXZfd/+fOOKUuGU+OGo7lqFLzuCSPLclRteSo7Pz+Y5KUfb96n9qckpuS3FFrflySm0pyR+3lx/2Z3HTNdG7xQT8AAF0ZTJWfdb0BAOChEgAAC97o
mcB35hfu1vx13raiHnDgdA5OL/tvL9m/X/OIJElJr47l4PtVVfjMAAAKY0lEQVT/v2WY7RlmS5LM9HPvfjOZmU5mZ3ce9Zb9F2XrYE3Ztkf/QADMK/+0rmxO
sn50/ZLBG+rima15QoZ5fEoOz87H2ixJyaGpWVKTJSU5tNYsKSWHJjloH87/1Uo2pWZzks1JNqVkc2o2lWTzMNncS+6sya0Zy213H5TbHWMKAAAAAHuGAABg
N43uwHcXPgD7xGB12ZIHeJbpL5qYqGPL+lmyfTyH9muW1JJHJkmGWVxL9kuS3s7H3yxKkmHNgSUZT5KUPDI1/VKyvdadAVuSbaVk687fIluz8+Sa1JotvV62
j/77rtLL5pnpbBoFDQAAAABABwQAAADQkKmpMjuVbMjOCwAAAABYQHpdDwAAAAAAAAAAHj4BAAAAAAAAAAA0QAAAAAAAAAAAAA0QAAAAAAAAAABAAwQAAAAA
AAAAANAAAQAAAAAAAAAANEAAAAAAAAAAAAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEAAAAAAAAAADRAAAAAAAAAAAAADRAAAAAAAAAAAEADBAAAAAAAAAAA
0AABAAAAAAAAAAA0QAAAAAAAAAAAAA0QAAAAAAAAAABAAwQAAAAAAAAAANAAAQAAAAAAAAAANEAAAAAAAAAAAAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEA
AAAAAAAAADRAAAAAAAAAAAAADRAAAAAAAAAAAEADBAAAAAAAAAAA0AABAAAAAAAAAAA0QAAAAAAAAAAAAA0QAAAAAAAAAABAAwQAAAAAAAAAANAAAQAAAAAA
AAAANEAAAAAAAAAAAAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEAAAAAAAAAADRAAAAAAAAAAAAADRAAAAAAAAAAAEADBAAAAAAAAAAA0AABAAAAAAAAAAA0
QAAAAAAAAAAAAA0QAAAAAAAAAABAAwQAAAAAAAAAANAAAQAAAAAAAAAANEAAAAAAAAAAAAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEAAAAAAAAAADRAAAAA
AAAAAAAADRAAAAAAAAAAAEADBAAAAAAAAAAA0AABAAAAAAAAAAA0QAAAAAAAAAAAAA0QAAAAAAAAAABAAwQAAAAAAAAAANAAAQAAAAAAAAAANEAAAAAAAAAA
AAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEAAAAAAAAAADRAAAAAAAAAAAAADRAAAAAAAAAAAEADBAAAAAAAAAAA0AABAAAAAAAAAAA0QAAAAAAAAAAAAA0Q
AAAAAAAAAABAAwQAAAAAAAAAANAAAQAAAAAAAAAANEAAAAAAAAAAAAANEAAAAAAAAAAAQAMEAAAAAAAAAADQAAEAAAAAAAAAADRAAAAAAAAAAAAADRAAAAAA
AAAAAEADBAAAAAAAAAAA0AABAAAAAAAAAAA0QAAAAAAAAAAAAA3odz0AAAAAAACY42ruSMn7u54BwDxRc1vXExYqAQAAAAAAAPCAzl1Xbknylq53AAAPzCMA
AAAAAAAAAKABAgAAAAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAA
AAAAoAECAAAAAAAAAABogAAAAAAAAAAAABogAAAAAAAAAACABggAAAAAAAAAAKABAgAAAAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACg
AQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAAAABogAAAAAAAAAAAABogAAAAAAAAAACABggAAAAAAAAAAKABAgAA
AAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAA
AABogAAAAAAAAAAAABogAAAAAAAAAACABggAAAAAAAAAAKABAgAAAAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiA
AAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAAAABogAAAAAAAAAAAABogAAAAAAAAAACABggAAAAAAAAAAKABAgAAAAAAAAAAaIAAAAAA
AAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAAAABogAAAAAAAAAAA
ABogAAAAAAAAAACABggAAAAAAAAAAKABAgAAAAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAAAAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAA
AAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAAAABogAAAAAAAAAAAABogAAAAAAAAAACABggAAAAAAAAAAKABAgAAAAAAAAAAaIAAAAAAAAAAAAAaIAAAAAAA
AAAAgAYIAAAAAAAAAACgAQIAAAAAAAAAAGiAAAAAAAAAAAAAGiAAAAAAAAAAAIAGCAAAAAAAAAAAoAECAAAAAAAAAABogAAAAAAAAAAAABogAAAAAAAAAACA
BggAAAAAAAAAAKAB/a4HsMtwOn8+3st41zt4cNPDTHe9AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgIXs
fwEVW5c3VklhuQAAAABJRU5ErkJggg==
'@
$script:AppDataDir = Join-Path $env:LOCALAPPDATA 'AgentPort'
$script:IconPath = Join-Path $script:AppDataDir 'AgentPort.ico'
function Ensure-AppIcon {
    try {
        if(-not (Test-Path -LiteralPath $script:AppDataDir)){ New-Item -ItemType Directory -Force -Path $script:AppDataDir | Out-Null }
        $bytes = [Convert]::FromBase64String(($script:AppIconBase64 -replace '\s',''))
        if((-not (Test-Path -LiteralPath $script:IconPath)) -or ((Get-Item -LiteralPath $script:IconPath).Length -ne $bytes.Length)){
            [IO.File]::WriteAllBytes($script:IconPath,$bytes)
        }
    } catch {}
}
Ensure-AppIcon

function Test-Port([int]$Port){
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1',$Port,$null,$null)
        if(-not $ar.AsyncWaitHandle.WaitOne(250)){ return $false }
        $client.EndConnect($ar)
        return $true
    } catch { return $false } finally { $client.Close() }
}

function Format-Size([double]$Bytes){
    if($Bytes -lt 1KB){ return ('{0:N0} B' -f $Bytes) }
    if($Bytes -lt 1MB){ return ('{0:N1} KB' -f ($Bytes/1KB)) }
    if($Bytes -lt 1GB){ return ('{0:N1} MB' -f ($Bytes/1MB)) }
    return ('{0:N2} GB' -f ($Bytes/1GB))
}

function Get-GpuInfo {
    try {
        $line = & nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if($line){
            $parts = $line -split ',' | ForEach-Object { $_.Trim() }
            return [pscustomobject]@{ Name=$parts[0]; Total=[math]::Round(([double]$parts[1]/1024),1); Free=[math]::Round(([double]$parts[2]/1024),1) }
        }
    } catch {}
    return [pscustomobject]@{ Name='NVIDIA GPU'; Total=16; Free=16 }
}

function Get-SystemRamGB {
    try { return [math]::Round(((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB),1) } catch { return 64 }
}

$script:Gpu = Get-GpuInfo
$script:RamGB = Get-SystemRamGB

function Add-ModelSearchRoot([System.Collections.ArrayList]$Roots,[string]$Path,[string]$Source){
    if([string]::IsNullOrWhiteSpace($Path)){ return }
    try{ $full=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) }catch{ return }
    if(Test-Path -LiteralPath $full){
        $key=$full.TrimEnd('\').ToLowerInvariant()
        if(-not ($Roots | Where-Object { $_.Key -eq $key })){ [void]$Roots.Add([pscustomobject]@{Path=$full; Source=$Source; Key=$key}) }
    }
}

function Read-ModelDirsFromJsonText([System.Collections.ArrayList]$Roots,[string]$Path,[string]$Source){
    try{
        if(-not(Test-Path -LiteralPath $Path)){ return }
        $txt=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        foreach($m in [regex]::Matches($txt,'(?i)"(modelsDirectory|modelDirectory|modelsPath|modelPath|modelDownloadDir|downloadDir)"\s*:\s*"([^"]+)"')){
            $p=$m.Groups[2].Value -replace '\\\\','\'
            Add-ModelSearchRoot $Roots $p $Source
        }
    }catch{}
}

function Get-ModelSearchRoots {
    $roots=New-Object System.Collections.ArrayList
    Add-ModelSearchRoot $roots ([string]$script:Config.models_root) 'AgentPort'
    Add-ModelSearchRoot $roots (Join-Path ([string]$script:Config.textgen_root) 'user_data\models') 'TextGen'
    Add-ModelSearchRoot $roots $env:OLLAMA_MODELS 'Ollama OLLAMA_MODELS'
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE '.ollama\models') 'Ollama default'
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE '.lmstudio\models') 'LM Studio'
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE '.cache\lm-studio\models') 'LM Studio legacy'
    Add-ModelSearchRoot $roots (Join-Path $env:APPDATA 'LM Studio') 'LM Studio config'
    Add-ModelSearchRoot $roots $env:UNSLOTH_STUDIO_HOME 'Unsloth Studio'
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE '.unsloth') 'Unsloth Studio'
    Add-ModelSearchRoot $roots (Join-Path $env:LOCALAPPDATA 'Unsloth Studio') 'Unsloth Studio'
    Add-ModelSearchRoot $roots $env:HF_HUB_CACHE 'Hugging Face cache'
    if($env:HF_HOME){ Add-ModelSearchRoot $roots (Join-Path $env:HF_HOME 'hub') 'Hugging Face HF_HOME' }
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE '.cache\huggingface\hub') 'Hugging Face default'
    Add-ModelSearchRoot $roots (Join-Path $env:APPDATA 'Jan\models') 'Jan'
    Add-ModelSearchRoot $roots (Join-Path $env:USERPROFILE 'jan\models') 'Jan'
    Add-ModelSearchRoot $roots (Join-Path $env:LOCALAPPDATA 'nomic.ai\GPT4All') 'GPT4All'
    Add-ModelSearchRoot $roots (Join-Path $env:APPDATA 'nomic.ai\GPT4All') 'GPT4All'
    foreach($cfg in @((Join-Path $env:APPDATA 'LM Studio'), (Join-Path $env:LOCALAPPDATA 'LM Studio'), (Join-Path $env:APPDATA 'Jan'), (Join-Path $env:LOCALAPPDATA 'Jan'))){
        if(Test-Path -LiteralPath $cfg){ Get-ChildItem -LiteralPath $cfg -Include *.json,*.jsonc -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 60 | ForEach-Object { Read-ModelDirsFromJsonText $roots $_.FullName ((Split-Path $cfg -Leaf)+' custom path') } }
    }
    $script:LastModelScanRoots=@($roots)
    return @($roots)
}

function Find-RelatedMmproj([string]$ModelPath){
    $dir=Split-Path $ModelPath -Parent
    if(-not(Test-Path -LiteralPath $dir)){ return @() }
    $helpers=@(Get-ChildItem -LiteralPath $dir -Filter 'mmproj*.gguf' -File -ErrorAction SilentlyContinue)
    if($helpers.Count -eq 0){ $helpers=@(Get-ChildItem -LiteralPath $dir -Filter '*mmproj*.gguf' -File -ErrorAction SilentlyContinue) }
    return @($helpers | Select-Object -ExpandProperty FullName)
}

function Get-InstalledModels {
    $items = @()
    $seen = @{}
    foreach($rootInfo in Get-ModelSearchRoots){
        $root=$rootInfo.Path
        if(-not(Test-Path -LiteralPath $root)){ continue }
        try{
            Get-ChildItem -LiteralPath $root -Filter '*.gguf' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(?i:mmproj)' -and $_.Name -notmatch '(?i)mmproj.*\.gguf$' } | Select-Object -First 800 | ForEach-Object {
                $key=$_.FullName.ToLowerInvariant()
                if($seen.ContainsKey($key)){ return }
                $seen[$key]=$true
                try { $rel = $_.FullName.Substring($root.TrimEnd('\').Length).TrimStart('\').Replace('\','/') } catch { $rel=$_.Name }
                $isMainRoot = ($root.TrimEnd('\').ToLowerInvariant() -eq ([string]$script:Config.models_root).TrimEnd('\').ToLowerInvariant())
                $modelId = if($isMainRoot){ $rel } else { $_.FullName }
                $helpers=@(Find-RelatedMmproj $_.FullName)
                $helperText = if($helpers.Count -gt 0){ ' | helper: '+([IO.Path]::GetFileName($helpers[0])) } else { '' }
                $source=[string]$rootInfo.Source
                $items += [pscustomobject]@{
                    Display = ('{0} | {1} | {2}{3}' -f $_.Name, (Format-Size $_.Length), $source, $helperText)
                    Name = $_.Name
                    RelPath = $modelId
                    FullPath = $_.FullName
                    Source = $source
                    RootPath = $root
                    HelperFiles = $helpers
                    SizeBytes = [double]$_.Length
                    SizeGB = [math]::Round(($_.Length/1GB),2)
                }
            }
        }catch{}
    }
    return @($items | Sort-Object Source,Name)
}

function Invoke-TextGenApi([string]$Path,[string]$Method='GET',$Body=$null,[int]$TimeoutSec=2){
    $headers = @{ Authorization='Bearer local-textgen'; Accept='application/json' }
    $params = @{ Uri=('http://127.0.0.1:5100'+$Path); Method=$Method; Headers=$headers; TimeoutSec=$TimeoutSec; ErrorAction='Stop' }
    if($null -ne $Body){ $params['ContentType']='application/json'; $params['Body']=($Body | ConvertTo-Json -Depth 8) }
    return Invoke-RestMethod @params
}

function Get-LoadedModel {
    if(-not (Test-Port 5100)){ return '' }
    try {
        $r = Invoke-TextGenApi '/v1/internal/model/info' 'GET' $null 1
        $n = [string]$r.model_name
        if($n -and $n -notin @('none','null')){ return $n }
    } catch {}
    try {
        $r = Invoke-TextGenApi '/v1/models' 'GET' $null 1
        if($r.data -and $r.data.Count -gt 0){ return [string]$r.data[0].id }
    } catch {}
    return ''
}

function Test-ModelMatch([string]$Expected,[string]$Actual){
    if(-not $Expected -or -not $Actual){ return $false }
    $e = [IO.Path]::GetFileNameWithoutExtension(($Expected -replace '/','\')).ToLowerInvariant()
    $a = [IO.Path]::GetFileNameWithoutExtension(($Actual -replace '/','\')).ToLowerInvariant()
    return ($e -eq $a -or $e.Contains($a) -or $a.Contains($e))
}

function Kill-Stack {
    $ports = @(3080,5100,5105,7860)
    foreach($p in $ports){
        Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -like '*llama-server.exe*' -or $_.CommandLine -like '*installer_files\env\python.exe*server.py*' -or $_.CommandLine -like '*dsh web*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Kill-HarnessOnly {
    Get-NetTCPConnection -State Listen -LocalPort 3080 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*dsh web*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Prepare-IsolatedHarnessSkills {
    $source = [string]$script:Config.harness_skills_root
    $harness = [string]$script:Config.harness_root
    if(-not (Test-Path $source)){ New-Item -ItemType Directory -Force -Path $source | Out-Null }
    $agents = Join-Path $harness '.agents'
    $active = Join-Path $agents 'skills'
    $backup = Join-Path $agents 'skills.original-before-studio'
    $marker = Join-Path $active '.managed-by-agentport'
    if(-not (Test-Path $agents)){ New-Item -ItemType Directory -Force -Path $agents | Out-Null }
    if((Test-Path $active) -and -not (Test-Path $marker)){
        if(-not (Test-Path $backup)){ Move-Item -LiteralPath $active -Destination $backup }
        else { Remove-Item -LiteralPath $active -Recurse -Force }
    }
    if(Test-Path $active){ Remove-Item -LiteralPath $active -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $active | Out-Null
    Get-ChildItem -LiteralPath $source -Force -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $active -Recurse -Force }
    'Managed by AgentPort. Put Harness-only skills in ~/.dsh/harness_skills.' | Set-Content -LiteralPath $marker -Encoding UTF8
}



function Ensure-DmSansFont {
    $fontDir=Join-Path $script:AppDataDir 'fonts'
    $regular=Join-Path $fontDir 'DMSans-Regular.ttf'
    $medium=Join-Path $fontDir 'DMSans-Medium.ttf'
    $bold=Join-Path $fontDir 'DMSans-Bold.ttf'
    if((Test-Path $regular) -and (Test-Path $medium) -and (Test-Path $bold)){ return $fontDir }
    try {
        if(-not(Test-Path $fontDir)){ New-Item -ItemType Directory -Force -Path $fontDir | Out-Null }
        $wc=New-Object System.Net.WebClient
        $wc.Headers['User-Agent']='AgentPort/1.2'
        $base='https://raw.githubusercontent.com/googlefonts/dm-fonts/main/Sans/Exports/'
        if(-not(Test-Path $regular)){ $wc.DownloadFile($base+'DMSans-Regular.ttf',$regular) }
        if(-not(Test-Path $medium)){ $wc.DownloadFile($base+'DMSans-Medium.ttf',$medium) }
        if(-not(Test-Path $bold)){ $wc.DownloadFile($base+'DMSans-Bold.ttf',$bold) }
        return $fontDir
    } catch { return $null }
}


function Pump-Ui {
    try {
        $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})
    } catch {}
}

function Set-LaunchPhase([int]$Step,[string]$Title,[string]$Detail,[double]$Percent,[string]$State='active'){
    $script:LaunchPhase=$Step
    if($null -eq $LaunchProgressCard){ return }
    $LaunchProgressCard.Visibility='Visible'
    $LaunchProgress.Value=[math]::Max(0,[math]::Min(100,$Percent))
    $LaunchPhaseText.Text=("Phase {0} of 7 - {1}" -f $Step,$Title)
    $LaunchPercentText.Text=('{0:N0}%' -f $LaunchProgress.Value)
    $LaunchDetailText.Text=$Detail
    switch($State){
        'error' { $LaunchProgress.Foreground='#FF6B78'; $LaunchPhaseText.Foreground='#FF9DA7'; $LaunchPercentText.Foreground='#FF9DA7' }
        'ok'    { $LaunchProgress.Foreground='#51E57A'; $LaunchPhaseText.Foreground='#8AF5B5'; $LaunchPercentText.Foreground='#8AF5B5' }
        default { $LaunchProgress.Foreground='#7B61FF'; $LaunchPhaseText.Foreground='#F1F1F4'; $LaunchPercentText.Foreground='#A99BFF' }
    }
    Pump-Ui
}

function Get-RecentLogText([string]$Path,[int]$Lines=12){
    try {
        if($Path -and (Test-Path -LiteralPath $Path)){
            return ((Get-Content -LiteralPath $Path -Tail $Lines -ErrorAction SilentlyContinue) -join ' | ')
        }
    } catch {}
    return ''
}

function Patch-TextGenLauncher {
    $root=[string]$script:Config.textgen_root
    $bat=Join-Path $root 'start_windows.bat'
    if(-not (Test-Path -LiteralPath $bat)){ return }
    try {
        $content=Get-Content -LiteralPath $bat -Raw
        # The upstream batch file intentionally ends with PAUSE for interactive users.
        # AgentPort launches it hidden, so that PAUSE would otherwise wait forever.
        $patched=[regex]::Replace($content,'(?im)^[ \t]*pause[ \t]*$','exit /b %errorlevel%')
        if($patched -ne $content){
            [IO.File]::WriteAllText($bat,$patched,([System.Text.UTF8Encoding]::new($false)))
        }
    } catch {}
}

function Ensure-AgentPortRuntimeDirs {
    foreach($dir in @($script:AppDataDir,$script:PublicDataDir,$script:NpmCacheDir,[string]$script:Config.models_root,[string]$script:Config.harness_root)){
        if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    }
}

function Get-AutoGpuChoice {
    try {
        if(& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1){ return 'A' }
    } catch {}
    try {
        $names = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Name })
        if($names -match 'Intel.*Arc'){ return 'D' }
    } catch {}
    return 'N'
}

function Ensure-PortableNode {
    if(Test-Path -LiteralPath $script:PortableNpx){ return $script:PortableNpx }
    Ensure-AgentPortRuntimeDirs
    $version=$script:PortableNodeVersion
    $archiveName="node-v$version-win-x64.zip"
    $url="https://nodejs.org/dist/v$version/$archiveName"
    $expectedSha='7df0bc9375723f4a86b3aa1b7cc73342423d9677a8df4538aca31a049e309c29'
    $zip=Join-Path $env:TEMP ('AgentPort-'+$archiveName)
    $extract=Join-Path $env:TEMP ('AgentPort-node-'+[guid]::NewGuid().ToString('N'))
    Set-Log 'Preparing the built-in Harness runtime (portable Node.js)...'
    try {
        $wc=New-Object System.Net.WebClient
        $wc.Headers['User-Agent']='AgentPort/1.2'
        $wc.DownloadFile($url,$zip)
        $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
        if($hash -ne $expectedSha){ throw 'Portable Node download failed integrity verification.' }
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $source=Join-Path $extract ("node-v$version-win-x64")
        if(-not (Test-Path -LiteralPath (Join-Path $source 'npx.cmd'))){ throw 'Portable Node archive was incomplete.' }
        if(Test-Path -LiteralPath $script:PortableNodeDir){ Remove-Item -LiteralPath $script:PortableNodeDir -Recurse -Force }
        Move-Item -LiteralPath $source -Destination $script:PortableNodeDir
        Set-Log 'Portable Harness runtime is ready.' 'ok'
        return $script:PortableNpx
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-TextGenSource {
    $root=[string]$script:Config.textgen_root
    $bat=Join-Path $root 'start_windows.bat'
    if(Test-Path -LiteralPath $bat){ Patch-TextGenLauncher; return }
    if($root -match '\s'){
        $root=Join-Path $script:PublicDataDir 'textgen'
        $script:Config.textgen_root=$root
        Save-Config
        try { Refresh-PathLabels } catch {}
    }
    $parent=Split-Path $root -Parent
    if(-not (Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    if(-not (Test-Path -LiteralPath $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
    $zip=Join-Path $env:TEMP ('AgentPort-textgen-'+[guid]::NewGuid().ToString('N')+'.zip')
    $extract=Join-Path $env:TEMP ('AgentPort-textgen-'+[guid]::NewGuid().ToString('N'))
    Set-Log 'Downloading the TextGen runtime source...'
    try {
        $wc=New-Object System.Net.WebClient
        $wc.Headers['User-Agent']='AgentPort/1.2'
        $wc.DownloadFile('https://github.com/oobabooga/text-generation-webui/archive/refs/heads/main.zip',$zip)
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $source=Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
        if($null -eq $source -or -not (Test-Path -LiteralPath (Join-Path $source.FullName 'start_windows.bat'))){ throw 'TextGen source archive was incomplete.' }
        Get-ChildItem -LiteralPath $source.FullName -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $root -Recurse -Force }
        Patch-TextGenLauncher
        Set-Log 'TextGen source is ready. Preparing its isolated Python/CUDA environment...' 'ok'
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Begin-TextGenBootstrap {
    Set-LaunchPhase 3 'Preparing TextGen runtime' 'Downloading the TextGen source and preparing the isolated installer.' 24
    Ensure-TextGenSource
    Patch-TextGenLauncher
    $root=[string]$script:Config.textgen_root
    $bat=Join-Path $root 'start_windows.bat'
    $logs=Join-Path $root 'logs'
    if(-not (Test-Path $logs)){ New-Item -ItemType Directory -Force -Path $logs | Out-Null }
    $script:BootstrapLog=Join-Path $logs 'agentport-first-run-install.log'
    $gpuChoice=Get-AutoGpuChoice
    $cmd='set "GPU_CHOICE={0}"&& set "LAUNCH_AFTER_INSTALL=FALSE"&& set "INSTALL_EXTENSIONS=FALSE"&& call "{1}" > "{2}" 2>&1' -f $gpuChoice,$bat,$script:BootstrapLog
    $script:BootstrapProcess=Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/s','/c',$cmd -WorkingDirectory $root -WindowStyle Hidden -PassThru
    $script:LaunchState='install_textgen'
    $script:LaunchDeadline=(Get-Date).AddMinutes(90)
    $PrimaryButton.IsEnabled=$false
    $PrimaryButton.Content='Installing TextGen runtime...'
    Set-LaunchPhase 3 'Installing TextGen runtime' ('GPU profile: '+$gpuChoice+'. First run can download around 10 GB.') 30
    Set-Log ('First-run setup started. GPU profile: '+$gpuChoice+'.')
}

function Test-TextGenInstalled {
    $root=[string]$script:Config.textgen_root
    $python=Join-Path $root 'installer_files\env\python.exe'
    $torch=Join-Path $root 'installer_files\env\Lib\site-packages\torch\__init__.py'
    $server=Join-Path $root 'server.py'
    return ((Test-Path -LiteralPath $python) -and (Test-Path -LiteralPath $torch) -and (Test-Path -LiteralPath $server))
}


function Get-TextGenInstallState {
    $root=[string]$script:Config.textgen_root
    $bat=Join-Path $root 'start_windows.bat'
    $python=Join-Path $root 'installer_files\env\python.exe'
    $torch=Join-Path $root 'installer_files\env\Lib\site-packages\torch\__init__.py'
    $server=Join-Path $root 'server.py'
    if(Test-TextGenInstalled){ return [pscustomobject]@{State='Installed'; Detail=$root; Kind='ok'} }
    if((Test-Path -LiteralPath $root) -and ((Test-Path -LiteralPath $bat) -or (Test-Path -LiteralPath $python) -or (Test-Path -LiteralPath $server))){ return [pscustomobject]@{State='Needs repair'; Detail='TextGen exists but required runtime files are missing'; Kind='warn'} }
    return [pscustomobject]@{State='Missing'; Detail='Click Install TextGen to download and prepare it'; Kind='missing'}
}

function Test-HarnessInstalled {
    if(Test-Path -LiteralPath (Join-Path ([string]$script:Config.harness_root) 'package.json')){ return $true }
    if(Test-Path -LiteralPath $script:PortableNpx){ return $true }
    return $false
}

function Get-HarnessInstallState {
    $root=[string]$script:Config.harness_root
    if(Test-Path -LiteralPath (Join-Path $root 'package.json')){ return [pscustomobject]@{State='Installed'; Detail=$root; Kind='ok'} }
    if(Test-Path -LiteralPath $script:PortableNpx){ return [pscustomobject]@{State='Installed'; Detail='Portable Node runtime ready. Harness runs through npx cache.'; Kind='ok'} }
    if(Test-Path -LiteralPath $root){ return [pscustomobject]@{State='Needs repair'; Detail='Harness workspace exists but runtime is not prepared'; Kind='warn'} }
    return [pscustomobject]@{State='Missing'; Detail='Click Install DeepSeek Harness to prepare it'; Kind='missing'}
}

function Set-InstallFlag($TextBlock,$Dot,[pscustomobject]$Info){
    if($null -eq $TextBlock){ return }
    $TextBlock.Text=$Info.State
    switch($Info.Kind){
        'ok' { $TextBlock.Foreground='#8AF5B5'; if($Dot){$Dot.Fill='#51E57A'} }
        'warn' { $TextBlock.Foreground='#F5D68A'; if($Dot){$Dot.Fill='#F5C45A'} }
        default { $TextBlock.Foreground='#FF9DA7'; if($Dot){$Dot.Fill='#FF6B78'} }
    }
}

function Refresh-InstallStatus {
    try{
        $tg=Get-TextGenInstallState
        $hs=Get-HarnessInstallState
        Set-InstallFlag $TextGenInstallFlag $TextGenInstallDot $tg
        Set-InstallFlag $HarnessInstallFlag $HarnessInstallDot $hs
        if($TextGenInstallDetail){ $TextGenInstallDetail.Text=$tg.Detail }
        if($HarnessInstallDetail){ $HarnessInstallDetail.Text=$hs.Detail }
    }catch{}
}

function Start-TextGenInstallOnly([bool]$Repair=$false){
    try{
        $script:InstallOnlyMode=$true
        if($Repair){
            $root=[string]$script:Config.textgen_root
            $ans=[System.Windows.MessageBox]::Show("Repair TextGen at:`n`n$root`n`nThis preserves user_data and models, but refreshes missing app/runtime files.",'Repair TextGen',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Information)
            if($ans -ne [System.Windows.MessageBoxResult]::Yes){ return }
        }
        Begin-TextGenBootstrap
        Refresh-InstallStatus
    }catch{ Set-Log $_.Exception.Message 'error'; [System.Windows.MessageBox]::Show($_.Exception.Message,'TextGen setup')|Out-Null }
}

function Install-DeepSeekHarness([bool]$Repair=$false){
    try{
        Set-LaunchPhase 1 'Preparing DeepSeek Harness' 'Installing portable Node and warming the DeepSeek Harness package cache.' 15
        Ensure-AgentPortRuntimeDirs
        if($Repair -and (Test-Path -LiteralPath $script:PortableNodeDir)){ Remove-Item -LiteralPath $script:PortableNodeDir -Recurse -Force -ErrorAction SilentlyContinue }
        $npx=Ensure-PortableNode
        $root=[string]$script:Config.harness_root
        if(-not(Test-Path -LiteralPath $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
        $logs=Join-Path ([string]$script:Config.textgen_root) 'logs'
        if(-not(Test-Path -LiteralPath $logs)){ New-Item -ItemType Directory -Force -Path $logs | Out-Null }
        $out=Join-Path $logs 'harness-install.out.log'
        $err=Join-Path $logs 'harness-install.err.log'
        Set-LaunchPhase 1 'Installing DeepSeek Harness' 'Downloading/caching Harness through portable npx.' 35
        $cmd='set "npm_config_cache={0}"&& "{1}" --yes @deepseek-ai/dsh@latest --help > "{2}" 2> "{3}"' -f $script:NpmCacheDir,$npx,$out,$err
        $p=Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/s','/c',$cmd -WorkingDirectory $root -WindowStyle Hidden -PassThru
        $p.WaitForExit(120000)
        if(-not $p.HasExited){ try{$p.Kill()}catch{}; throw 'DeepSeek Harness install timed out while preparing npx cache.' }
        if($p.ExitCode -ne 0){
            $detail=Get-RecentLogText $err 12
            if(-not $detail){$detail=Get-RecentLogText $out 12}
            if(-not $detail){$detail='npx exited with code '+$p.ExitCode}
            throw $detail
        }
        'AgentPort Harness workspace. Do not delete unless you want to reset the local Harness runtime.' | Set-Content -LiteralPath (Join-Path $root 'README.agentport.txt') -Encoding UTF8
        Set-LaunchPhase 1 'DeepSeek Harness ready' 'Harness runtime is prepared. You can now Apply & Start.' 100 'ok'
        Set-Log 'DeepSeek Harness runtime is installed and ready.' 'ok'
        Refresh-InstallStatus
    }catch{ Set-LaunchPhase 1 'DeepSeek Harness install failed' $_.Exception.Message 100 'error'; Set-Log $_.Exception.Message 'error'; [System.Windows.MessageBox]::Show($_.Exception.Message,'DeepSeek Harness setup')|Out-Null }
}

function Scan-Models {
    Refresh-Models
    $rootCount=@($script:LastModelScanRoots).Count
    $modelCount=@($script:Models).Count
    Set-Log ("Model scan complete. Found $modelCount GGUF model(s) across $rootCount known local AI location(s).") 'ok'
    if($modelCount -eq 0){ [System.Windows.MessageBox]::Show('No GGUF models were found. Try Hugging Face download, Import GGUF, or change the Models path in Settings.','Scan models')|Out-Null }
}

function Add-SkillFolder {
    $src=Choose-Folder $env:USERPROFILE
    if(-not $src){ return }
    try{
        $root=[string]$script:Config.harness_skills_root
        if(-not(Test-Path $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
        $dest=Join-Path $root ([IO.Path]::GetFileName($src.TrimEnd('\')))
        Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
        Refresh-SkillsPanel; Set-Log ('Added Harness skill folder: '+[IO.Path]::GetFileName($dest)) 'ok'
    }catch{ [System.Windows.MessageBox]::Show($_.Exception.Message,'Add skill')|Out-Null }
}

function Import-SkillZip {
    $dlg=New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title='Import Harness skill ZIP'
    $dlg.Filter='ZIP archive (*.zip)|*.zip|All files (*.*)|*.*'
    if($dlg.ShowDialog() -ne $true){ return }
    try{
        $root=[string]$script:Config.harness_skills_root
        if(-not(Test-Path $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
        $name=[IO.Path]::GetFileNameWithoutExtension($dlg.FileName) -replace '[^a-zA-Z0-9._-]','-'
        $dest=Join-Path $root $name
        if(Test-Path $dest){ Remove-Item -LiteralPath $dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Expand-Archive -LiteralPath $dlg.FileName -DestinationPath $dest -Force
        Refresh-SkillsPanel; Set-Log ('Imported Harness skill ZIP: '+$name) 'ok'
    }catch{ [System.Windows.MessageBox]::Show($_.Exception.Message,'Import skill')|Out-Null }
}

function Create-BlankSkill {
    try{ Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue }catch{}
    $name=[Microsoft.VisualBasic.Interaction]::InputBox('Skill folder name:', 'Create Harness skill', 'my-harness-skill')
    if([string]::IsNullOrWhiteSpace($name)){ return }
    $safe=$name.Trim() -replace '[^a-zA-Z0-9._-]','-'
    $root=[string]$script:Config.harness_skills_root
    $dest=Join-Path $root $safe
    if(-not(Test-Path $dest)){ New-Item -ItemType Directory -Force -Path $dest | Out-Null }
    $skillMd=Join-Path $dest 'skill.md'
    if(-not(Test-Path $skillMd)){
@"
# $safe

Describe what this DeepSeek Harness skill should do.

Keep instructions simple and action-focused. Add any helper files beside this file.
"@ | Set-Content -LiteralPath $skillMd -Encoding UTF8
    }
    Refresh-SkillsPanel
    Start-Process explorer.exe $dest
    Set-Log ('Created blank Harness skill: '+$safe) 'ok'
}

function Write-TextGenFlags([string]$Model,[int]$Context,[string]$Cache,[string]$Offload,[string]$SpecMode){
    $flagsFile = Join-Path ([string]$script:Config.textgen_root) 'user_data\CMD_FLAGS.txt'
    $dir = Split-Path $flagsFile -Parent
    if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $mode = $script:OffloadModes[$Offload]
    $modelDir=[string]$script:Config.models_root
    $modelName=$Model
    if([IO.Path]::IsPathRooted($Model)){
        $modelDir=Split-Path $Model -Parent
        $modelName=Split-Path $Model -Leaf
    }
    $lines = @(
        '--api',
        '--api-port 5100',
        '--api-key local-textgen',
        ('--model-dir "{0}"' -f $modelDir),
        ('--model "{0}"' -f $modelName),
        '--loader llama.cpp',
        ('--ctx-size {0}' -f $Context),
        ('--cache-type {0}' -f $Cache),
        ('--gpu-layers {0}' -f $mode.gpu_layers),
        '--parallel 1'
    )
    if($null -ne $mode.fit_target){ $lines += ('--fit-target {0}' -f $mode.fit_target) }
    # Model-agnostic speculative decoding. ngram-mod works without requiring an MTP-specific GGUF.
    switch($SpecMode){
        'Conservative' { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 16'; $lines += '--spec-ngram-size-m 32' }
        'Medium'       { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 24'; $lines += '--spec-ngram-size-m 48' }
        'Aggressive'   { $lines += '--spec-type ngram-mod'; $lines += '--spec-ngram-size-n 32'; $lines += '--spec-ngram-size-m 64' }
    }
    if([IO.Path]::IsPathRooted($Model)){
        $helper = @(Find-RelatedMmproj $Model) | Select-Object -First 1
        if($helper){ $lines += ('--mmproj "{0}"' -f $helper) }
    } else {
        $abs = Join-Path ([string]$script:Config.models_root) ($Model -replace '/','\')
        $helper = @(Find-RelatedMmproj $abs) | Select-Object -First 1
        if($helper){ $lines += ('--mmproj "{0}"' -f $helper) }
    }
    [IO.File]::WriteAllLines($flagsFile,$lines,[Text.Encoding]::ASCII)
}

function Update-HarnessSettings([string]$Model,[string]$DisplayName,[int]$Context,[int]$MaxTokens){
    Ensure-ConfigDir
    $safeModel=$Model.Replace("'","''")
    $safeName=$DisplayName.Replace("'","''")
    if(-not (Test-Path -LiteralPath $script:SettingsPath)){
        $fresh=@"
llm-pi-ai:
  providers:
    textgen-local:
      displayName: TextGen Local
      apiKeyEnv: TEXTGEN_API_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:5100/v1
      defaultInput:
        - text
      timeoutMs: 3600000
      streamIdleTimeoutMs: 3600000
      websocketConnectTimeoutMs: 3600000
      retryPolicy:
        mode: normal
        maxRetries: 0
      models:
        - id: '$safeModel'
          name: '$safeName'
          contextWindow: $Context
          maxTokens: $MaxTokens
agent-default-model:
  provider: textgen-local
  model: '$safeModel'
"@
        [IO.File]::WriteAllText($script:SettingsPath,$fresh,([System.Text.UTF8Encoding]::new($false)))
        return
    }
    $content = Get-Content -LiteralPath $script:SettingsPath -Raw
    if($content -notmatch '(?m)^\s{4}textgen-local:\s*$'){
        $provider=@"
    textgen-local:
      displayName: TextGen Local
      apiKeyEnv: TEXTGEN_API_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:5100/v1
      defaultInput:
        - text
      timeoutMs: 3600000
      streamIdleTimeoutMs: 3600000
      websocketConnectTimeoutMs: 3600000
      retryPolicy:
        mode: normal
        maxRetries: 0
      models:
        - id: '$safeModel'
          name: '$safeName'
          contextWindow: $Context
          maxTokens: $MaxTokens
"@
        if($content -match '(?m)^\s{2}providers:\s*$'){
            $content=[regex]::Replace($content,'(?m)^(\s{2}providers:\s*\r?\n)',('${1}'+$provider+"`n"),1)
        } else {
            $content="llm-pi-ai:`n  providers:`n$provider`n"+$content
        }
    } else {
        $escaped = [regex]::Escape($Model)
        if($content.Contains($Model)){
            $content = [regex]::Replace($content, "(- id:\s*['`"]?$escaped['`"]?\s+name:\s*[^\r\n]+\s+contextWindow:\s*)\d+", ('${1}'+$Context))
            $content = [regex]::Replace($content, "(- id:\s*['`"]?$escaped['`"]?[\s\S]*?contextWindow:\s*$Context[\s\S]*?maxTokens:\s*)\d+", ('${1}'+$MaxTokens))
        } else {
            $block = "        - id: '$safeModel'`n          name: '$safeName'`n          contextWindow: $Context`n          maxTokens: $MaxTokens`n"
            $content = [regex]::Replace($content, '(textgen-local:\s*[\r\n]+(?:[ \t]+[^\r\n]*[\r\n]+)*?[ \t]+models:\s*[\r\n]+)', ('${1}'+$block),1)
        }
    }
    if($content -match '(?m)^agent-default-model:\s*$'){
        $content = [regex]::Replace($content, '(agent-default-model:\s*[\r\n]+\s*provider:\s*)[^\r\n]+([\r\n]+\s*model:\s*)[^\r\n]+', ('${1}textgen-local${2}'+("'$safeModel'")))
    } else {
        $content += "`nagent-default-model:`n  provider: textgen-local`n  model: '$safeModel'`n"
    }
    [IO.File]::WriteAllText($script:SettingsPath,$content,([System.Text.UTF8Encoding]::new($false)))
}

function Start-TextGen {
    $root = [string]$script:Config.textgen_root
    if($root -match '\s'){ throw "TextGen cannot run from a path containing spaces: $root" }
    Patch-TextGenLauncher
    $python = Join-Path $root 'installer_files\env\python.exe'
    $conda = Join-Path $root 'installer_files\conda\condabin\conda.bat'
    $server = Join-Path $root 'server.py'
    if(-not (Test-Path -LiteralPath $python)){ throw "TextGen Python runtime is missing: $python" }
    if(-not (Test-Path -LiteralPath $conda)){ throw "TextGen Conda activation script is missing: $conda" }
    if(-not (Test-Path -LiteralPath $server)){ throw "TextGen server.py is missing: $server" }
    $logs = Join-Path $root 'logs'
    if(-not (Test-Path $logs)){ New-Item -ItemType Directory -Force -Path $logs | Out-Null }
    $out = Join-Path $logs 'textgen.out.log'
    $err = Join-Path $logs 'textgen.err.log'
    Remove-Item -LiteralPath $out,$err -Force -ErrorAction SilentlyContinue
    $envDir=Join-Path $root 'installer_files\env'
    $cmd='set "PYTHONNOUSERSITE=1"&& set "PYTHONPATH="&& set "PYTHONHOME="&& set "PYTHONUTF8=1"&& set "CUDA_PATH={0}"&& set "CUDA_HOME={0}"&& call "{1}" activate "{0}" && "{2}" server.py > "{3}" 2> "{4}"' -f $envDir,$conda,$python,$out,$err
    $script:TextGenProcess=Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/s','/c',$cmd -WorkingDirectory $root -WindowStyle Hidden -PassThru
    Set-Log ('TextGen process started (PID '+$script:TextGenProcess.Id+'). Waiting for API :5100...')
}

function Start-Harness {
    Ensure-AgentPortRuntimeDirs
    $root=[string]$script:Config.harness_root
    if(-not (Test-Path -LiteralPath $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
    Prepare-IsolatedHarnessSkills
    $logs = Join-Path ([string]$script:Config.textgen_root) 'logs'
    if(-not (Test-Path $logs)){ New-Item -ItemType Directory -Force -Path $logs | Out-Null }
    $out = Join-Path $logs 'harness.out.log'
    $err = Join-Path $logs 'harness.err.log'
    if(Test-Path -LiteralPath (Join-Path $root 'package.json')){
        $cmd = 'set "TEXTGEN_API_KEY=local-textgen"&& set "UNSLOTH_STUDIO_API_KEY=local-textgen"&& set "FREETOKEN_API_KEY=local-textgen"&& set "DSH_STUDIO_MODEL={0}"&& set "DSH_STUDIO_CONTEXT={1}"&& corepack pnpm dsh web --no-open > "{2}" 2> "{3}"' -f $script:PendingModel,$script:PendingContext,$out,$err
    } else {
        $npx=Ensure-PortableNode
        $cmd = 'set "TEXTGEN_API_KEY=local-textgen"&& set "UNSLOTH_STUDIO_API_KEY=local-textgen"&& set "FREETOKEN_API_KEY=local-textgen"&& set "DSH_STUDIO_MODEL={0}"&& set "DSH_STUDIO_CONTEXT={1}"&& set "npm_config_cache={2}"&& "{3}" --yes @deepseek-ai/dsh@latest web --no-open > "{4}" 2> "{5}"' -f $script:PendingModel,$script:PendingContext,$script:NpmCacheDir,$npx,$out,$err
    }
    Start-Process -FilePath 'cmd.exe' -ArgumentList '/d','/s','/c',$cmd -WorkingDirectory $root -WindowStyle Hidden | Out-Null
}

function Set-Log([string]$Text,[string]$Kind='normal'){
    $time = Get-Date -Format 'HH:mm:ss'
    $prefix = if($Kind -eq 'error'){'ERROR'} elseif($Kind -eq 'ok'){'OK'} else {'INFO'}
    $line = "[$time] $prefix  $Text`r`n"
    $LogBox.AppendText($line)
    $LogBox.ScrollToEnd()
    $StatusText.Text = $Text
}

function Set-PillState($Element,[string]$Text,[string]$State){
    $Element.Text = $Text
    switch($State){
        'online' { $Element.Foreground='#8AF5B5'; $Element.Parent.Background='#123423'; $Element.Parent.BorderBrush='#1C5B39' }
        'busy' { $Element.Foreground='#F5D68A'; $Element.Parent.Background='#3B2C12'; $Element.Parent.BorderBrush='#6B5120' }
        'purple' { $Element.Foreground='#C9B9FF'; $Element.Parent.Background='#221A3D'; $Element.Parent.BorderBrush='#4C3A82' }
        default { $Element.Foreground='#8A8A9A'; $Element.Parent.Background='#111118'; $Element.Parent.BorderBrush='#242431' }
    }
}

function Refresh-Models {
    $script:Models = @(Get-InstalledModels)
    $ModelCombo.Items.Clear()
    foreach($m in $script:Models){ [void]$ModelCombo.Items.Add($m.Display) }
    if($script:Models.Count -gt 0){
        $idx = 0
        if($script:Config.last_model){
            for($i=0;$i -lt $script:Models.Count;$i++){ if($script:Models[$i].RelPath -eq $script:Config.last_model){$idx=$i;break} }
        }
        $ModelCombo.SelectedIndex = $idx
    }
    Refresh-ModelManager
    Update-MemoryFit
}

function Get-SelectedModel {
    $i = $ModelCombo.SelectedIndex
    if($i -lt 0 -or $i -ge $script:Models.Count){ return $null }
    return $script:Models[$i]
}

function Update-MemoryFit {
    $m = Get-SelectedModel
    if($null -eq $m){
        foreach($bar in @($VramBar,$RamBar,$HomeVramBar,$HomeRamBar)){ if($null -ne $bar){ $bar.Value=0 } }
        $MemorySummary.Text='Install or select a GGUF model to estimate memory use.'
        $HomeMemorySummary.Text='Install or select a GGUF model to estimate memory use.'
        $HomeFitStatus.Text='No model selected'
        $HomeFitStatus.Foreground='#8A8A94'
        $VramText.Text='-'; $RamText.Text='-'; $HomeVramText.Text='-'; $HomeRamText.Text='-'
        return
    }

    $ctxLabel = [string]$ContextCombo.SelectedItem
    if(-not $ctxLabel){ $ctxLabel='48k (49,152 tokens)' }
    $ctx = [double]$script:ContextPresets[$ctxLabel]

    $cache = [string]$CacheCombo.SelectedItem
    if(-not $cache){ $cache='q4_0' }
    $bytesPer = if($cache -eq 'q4_0'){0.5}else{2.0}

    # Approximation tuned for llama.cpp GGUF planning. This is deliberately presented as
    # an estimate: actual allocations vary by architecture, mmap, backend and cache layout.
    $kv = ($ctx * 131072 * $bytesPer) / 1GB
    $overhead = 0.9
    $modelGB = [double]$m.SizeGB
    $totalNeed = $modelGB + $kv + $overhead

    $offload = [string]$OffloadCombo.SelectedItem
    if(-not $offload){ $offload='Auto Fit (Recommended)' }

    $vramTotal = [double]$script:Gpu.Total
    $ramTotal = [double]$script:RamGB
    $reserve = 0.75
    if($offload -eq 'Auto Fit (Safe Headroom)'){ $reserve = 2.0 }
    elseif($offload -eq 'Maximum GPU (Aggressive)'){ $reserve = 0.15 }

    if($offload -eq 'CPU / RAM Only'){
        # gpu-layers=0 leaves weights in system RAM. KV/compute allocations may still touch VRAM.
        $vUsed = [math]::Min($vramTotal, $kv + $overhead)
        $ramModel = $modelGB
        $spill = $ramModel
        $gpuTarget = [math]::Max(0.1, $vramTotal - $reserve)
    } else {
        $gpuTarget = [math]::Max(0.1, $vramTotal - $reserve)
        $vUsed = [math]::Min($totalNeed, $gpuTarget)
        $spill = [math]::Max(0, $totalNeed - $vUsed)
    }

    $baseSystem = 6.0
    $ramUsedEstimate = [math]::Min($ramTotal, $baseSystem + $spill)
    $vPct = [math]::Min(100, ($vUsed/[math]::Max(0.1,$vramTotal))*100)
    $rPct = [math]::Min(100, ($ramUsedEstimate/[math]::Max(0.1,$ramTotal))*100)

    $VramBar.Value=$vPct; $RamBar.Value=$rPct; $HomeVramBar.Value=$vPct; $HomeRamBar.Value=$rPct
    $VramText.Text = ('{0:N1} / {1:N1} GB' -f $vUsed,$vramTotal)
    $RamText.Text = ('{0:N1} GB model spill | {1:N1} GB system' -f $spill,$ramTotal)
    $HomeVramText.Text = ('{0:N1} / {1:N1} GB' -f $vUsed,$vramTotal)
    $HomeRamText.Text = if($spill -gt 0){ ('+{0:N1} GB spill' -f $spill) } else { 'No spill' }

    $availableCombined = $gpuTarget + [math]::Max(0,$ramTotal-$baseSystem)
    if($offload -eq 'CPU / RAM Only'){
        if(($modelGB+$baseSystem) -lt ($ramTotal*0.9)){
            $tier='RAM mode'
            $detail=('Weights stay in system RAM. Approx {0:N1} GB model + {1:N1} GB KV/cache.' -f $modelGB,$kv)
            $color='#B8A8FF'
        } else {
            $tier='RAM pressure'
            $detail=('Model is close to available system memory. Approx {0:N1} GB required.' -f ($modelGB+$kv+$baseSystem))
            $color='#FF9C9C'
        }
    } elseif($spill -le 0.15){
        $headroom=[math]::Max(0,$vramTotal-$vUsed)
        $tier='Fits fully in VRAM'
        $detail=('{0:N1} GB estimated footprint, {1:N1} GB VRAM headroom at {2:N0}k context.' -f $totalNeed,$headroom,($ctx/1024))
        $color='#79E99A'
    } elseif($totalNeed -lt $availableCombined*0.92){
        $tier='Partial GPU offload'
        $detail=('{0:N1} GB VRAM + {1:N1} GB RAM spill. Expected to run, but slower than full GPU.' -f $vUsed,$spill)
        $color='#F1C66D'
    } else {
        $tier='Memory pressure'
        $detail=('{0:N1} GB estimated requirement is close to/exceeds safe available memory. Reduce context, use q4_0 cache or a smaller quant.' -f $totalNeed)
        $color='#FF8E8E'
    }

    $MemorySummary.Text=$detail
    $MemorySummary.Foreground=$color
    $HomeFitStatus.Text=$tier
    $HomeFitStatus.Foreground=$color
    $HomeMemorySummary.Text=$detail
    $HomeMemorySummary.Foreground='#8F9099'
}
function Refresh-ModelManager {
    $ModelListPanel.Children.Clear()
    if($script:Models.Count -eq 0){
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text='No GGUF models found in your models folder.'; $t.Foreground='#8A8A9A'; $t.Margin='4,8,4,8'
        [void]$ModelListPanel.Children.Add($t); return
    }
    foreach($m in $script:Models){
        $row = New-Object System.Windows.Controls.Border
        $row.CornerRadius='18'; $row.Background='#0F0F16'; $row.BorderBrush='#1D1D29'; $row.BorderThickness='1'; $row.Padding='14'; $row.Margin='0,0,0,10'
        $grid = New-Object System.Windows.Controls.Grid
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='*'}))
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))
        $stack = New-Object System.Windows.Controls.StackPanel
        $name = New-Object System.Windows.Controls.TextBlock; $name.Text=$m.Name; $name.Foreground='White'; $name.FontWeight='SemiBold'; $name.FontSize=14
        $meta = New-Object System.Windows.Controls.TextBlock; $meta.Text=((Format-Size $m.SizeBytes)+'   |   '+$m.RelPath); $meta.Foreground='#777788'; $meta.FontSize=11; $meta.Margin='0,4,8,0'
        [void]$stack.Children.Add($name); [void]$stack.Children.Add($meta)
        [System.Windows.Controls.Grid]::SetColumn($stack,0); [void]$grid.Children.Add($stack)
        $btn = New-Object System.Windows.Controls.Button; $btn.Content='Delete'; $btn.Tag=$m.FullPath; $btn.Style=$Window.FindResource('DangerButton'); $btn.Padding='14,8'; $btn.Margin='12,0,0,0'
        $btn.Add_Click({ param($s,$e)
            $path=[string]$s.Tag
            $answer=[System.Windows.MessageBox]::Show("Permanently delete this model?`n`n$path",'Delete model',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
            if($answer -eq [System.Windows.MessageBoxResult]::Yes){ try{ Remove-Item -LiteralPath $path -Force; Set-Log 'Model deleted.' 'ok'; Refresh-Models }catch{ [System.Windows.MessageBox]::Show($_.Exception.Message,'Delete failed') } }
        })
        [System.Windows.Controls.Grid]::SetColumn($btn,1); [void]$grid.Children.Add($btn)
        $row.Child=$grid; [void]$ModelListPanel.Children.Add($row)
    }
}

function Choose-Folder([string]$Current){
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath=$Current
    $dlg.ShowNewFolderButton=$true
    if($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){ return $dlg.SelectedPath }
    return $null
}

function Switch-Page([string]$Name){
    foreach($p in @('Home','Models','Runtimes','Skills','Settings')){
        $v = Get-Variable -Name ($p+'Page') -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if($v){ $v.Visibility='Collapsed' }
    }
    $target = Get-Variable -Name ($Name+'Page') -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if($target){ $target.Visibility='Visible' }
    foreach($n in @('Home','Models','Runtimes','Skills','Settings')){
        $b = Get-Variable -Name ('Nav'+$n) -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if($b){ $b.Tag = if($n -eq $Name){'active'}else{'inactive'} }
    }
    if($Name -eq 'Skills'){ Refresh-SkillsPanel }
}

function Parse-HfRepo([string]$Input){
    $x=$Input.Trim() -replace '^https?://','' -replace '^huggingface\.co/',''
    $x=$x.Trim('/')
    $parts=$x -split '/'
    if($parts.Count -ge 2){ return ($parts[0]+'/'+$parts[1]) }
    return $x
}

function Inspect-HfRepo {
    try{
        $repo=Parse-HfRepo $RepoInput.Text
        if(-not $repo.Contains('/')){ throw 'Enter a Hugging Face repository URL or owner/repo ID.' }
        $InspectButton.IsEnabled=$false; $InspectButton.Content='Checking...'; $RepoStatus.Text='Reading GGUF files from Hugging Face...'
        $url='https://huggingface.co/api/models/'+$repo+'/tree/main'
        $data=Invoke-RestMethod -Uri $url -TimeoutSec 20 -Headers @{'User-Agent'='AgentPort/1.0'}
        $script:RepoFiles=@()
        $RepoFileCombo.Items.Clear()
        foreach($item in $data){
            $path=[string]$item.path
            if($path -like '*.gguf' -and [IO.Path]::GetFileName($path) -notlike 'mmproj-*'){
                $size=0; if($item.lfs -and $item.lfs.size){$size=[double]$item.lfs.size}elseif($item.size){$size=[double]$item.size}
                $obj=[pscustomobject]@{ Repo=$repo; Path=$path; Size=$size; Display=([IO.Path]::GetFileName($path)+'   |   '+(Format-Size $size)) }
                $script:RepoFiles += $obj; [void]$RepoFileCombo.Items.Add($obj.Display)
            }
        }
        if($script:RepoFiles.Count -gt 0){ $RepoFileCombo.SelectedIndex=0; $RepoStatus.Text=('{0} GGUF files found. Choose the quant you want.' -f $script:RepoFiles.Count) } else { $RepoStatus.Text='No GGUF files found in the repository root.' }
    }catch{ $RepoStatus.Text=$_.Exception.Message; [System.Windows.MessageBox]::Show($_.Exception.Message,'Hugging Face') | Out-Null }
    finally{ $InspectButton.IsEnabled=$true; $InspectButton.Content='Inspect files' }
}

function Start-HfDownload {
    $i=$RepoFileCombo.SelectedIndex
    if($i -lt 0 -or $i -ge $script:RepoFiles.Count){ [System.Windows.MessageBox]::Show('Choose a GGUF file first.','Install model') | Out-Null; return }
    $f=$script:RepoFiles[$i]
    $folder=($f.Repo -replace '/','_')
    $targetDir=Join-Path ([string]$script:Config.models_root) $folder
    if(-not (Test-Path $targetDir)){New-Item -ItemType Directory -Force -Path $targetDir|Out-Null}
    $dest=Join-Path $targetDir ([IO.Path]::GetFileName($f.Path))
    $url='https://huggingface.co/'+$f.Repo+'/resolve/main/'+($f.Path -replace ' ','%20')+'?download=true'
    $jobName='DSH_'+([guid]::NewGuid().ToString('N'))
    try{
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $url -Destination $dest -DisplayName $jobName -Asynchronous | Out-Null
        $script:Download=[pscustomobject]@{Name=$jobName;Dest=$dest;Expected=[double]$f.Size}
        $DownloadButton.IsEnabled=$false; $DownloadProgress.Value=0; $RepoStatus.Text='Downloading model... you can keep using the manager.'; Set-Log ('Downloading '+$f.Path)
    }catch{
        [System.Windows.MessageBox]::Show('Could not start Windows BITS download: '+$_.Exception.Message,'Download failed')|Out-Null
    }
}

function Poll-Download {
    if($null -eq $script:Download){ return }
    try{
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        $j=Get-BitsTransfer -Name $script:Download.Name -ErrorAction SilentlyContinue
        if($null -eq $j){ return }
        if($j.BytesTotal -gt 0){ $DownloadProgress.Value=[math]::Min(100,($j.BytesTransferred/$j.BytesTotal)*100); $RepoStatus.Text=('Downloading | {0:N1}% | {1} / {2}' -f $DownloadProgress.Value,(Format-Size $j.BytesTransferred),(Format-Size $j.BytesTotal)) }
        if($j.JobState -eq 'Transferred'){
            Complete-BitsTransfer -BitsJob $j
            $DownloadProgress.Value=100; $DownloadButton.IsEnabled=$true; $RepoStatus.Text='Installed. The model is ready on the Home screen.'; Set-Log 'Model download complete.' 'ok'; $script:Download=$null; Refresh-Models; Switch-Page 'Home'
        } elseif($j.JobState -in @('Error','TransientError')){
            $msg=[string]$j.ErrorDescription; Remove-BitsTransfer -BitsJob $j -Confirm:$false -ErrorAction SilentlyContinue; $script:Download=$null; $DownloadButton.IsEnabled=$true; $RepoStatus.Text='Download failed: '+$msg; Set-Log $msg 'error'
        }
    }catch{}
}


function Import-LocalGguf {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title='Import local GGUF model'
    $dlg.Filter='GGUF model (*.gguf)|*.gguf|All files (*.*)|*.*'
    if($dlg.ShowDialog() -ne $true){ return }
    try{
        $src=$dlg.FileName
        $stem=[IO.Path]::GetFileNameWithoutExtension($src)
        $targetDir=Join-Path ([string]$script:Config.models_root) $stem
        if(-not(Test-Path $targetDir)){New-Item -ItemType Directory -Force -Path $targetDir|Out-Null}
        $dest=Join-Path $targetDir ([IO.Path]::GetFileName($src))
        Copy-Item -LiteralPath $src -Destination $dest -Force
        $helpers=@(Find-RelatedMmproj $src)
        foreach($h in $helpers){ Copy-Item -LiteralPath $h -Destination (Join-Path $targetDir ([IO.Path]::GetFileName($h))) -Force }
        if($helpers.Count -gt 0){
            Set-Log ('Imported '+[IO.Path]::GetFileName($src)+' and its helper file: '+[IO.Path]::GetFileName($helpers[0])) 'ok'
        } else {
            $ask=[System.Windows.MessageBox]::Show(
                "Does this model need a vision/audio projector (mmproj) helper file?`n`nText-only models do not need one. Multimodal GGUF models ship a separate mmproj-*.gguf file. If you have it, choose it now and AgentPort will install it alongside the model and pass --mmproj automatically.",
                'Import helper (mmproj) file?',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question)
            if($ask -eq [System.Windows.MessageBoxResult]::Yes){
                $hdlg=New-Object Microsoft.Win32.OpenFileDialog
                $hdlg.Title='Import projector / helper (mmproj) GGUF'
                $hdlg.Filter='Projector helper (*mmproj*.gguf)|*mmproj*.gguf|GGUF file (*.gguf)|*.gguf|All files (*.*)|*.*'
                try{ $hdlg.InitialDirectory=[IO.Path]::GetDirectoryName($src) }catch{}
                if($hdlg.ShowDialog() -eq $true){
                    Copy-Item -LiteralPath $hdlg.FileName -Destination (Join-Path $targetDir ([IO.Path]::GetFileName($hdlg.FileName))) -Force
                    Set-Log ('Imported '+[IO.Path]::GetFileName($src)+' with helper file: '+[IO.Path]::GetFileName($hdlg.FileName)) 'ok'
                } else {
                    Set-Log ('Imported '+[IO.Path]::GetFileName($src)+' (no helper selected).') 'ok'
                }
            } else {
                Set-Log ('Imported '+[IO.Path]::GetFileName($src)+' (text-only, no helper needed).') 'ok'
            }
        }
        Refresh-Models; Switch-Page 'Home'
    }catch{ [System.Windows.MessageBox]::Show($_.Exception.Message,'Import failed')|Out-Null }
}

function Start-UnifiedStack {
    $m=Get-SelectedModel
    if($null -eq $m){ [System.Windows.MessageBox]::Show('Install or select a GGUF model first.','No model selected')|Out-Null; return }
    $ctxLabel=[string]$ContextCombo.SelectedItem; if(-not $ctxLabel){$ctxLabel='48k (49,152 tokens)'}
    $ctx=[int]$script:ContextPresets[$ctxLabel]
    $cache=[string]$CacheCombo.SelectedItem; if(-not $cache){$cache='q4_0'}
    $offload=[string]$OffloadCombo.SelectedItem; if(-not $offload){$offload='Auto Fit (Recommended)'}
    $spec=[string]$SpecCombo.SelectedItem; if(-not $spec){$spec='Medium'}
    $max=2048
    if($MaxTokensCombo.SelectedItem){ [int]::TryParse(([string]$MaxTokensCombo.SelectedItem -replace ',',''),[ref]$max) | Out-Null }
    $max=[math]::Min($max,$ctx)
    try{
        $script:InstallOnlyMode=$false
        $PrimaryButton.IsEnabled=$false
        Set-LaunchPhase 1 'Preflight' 'Checking folders, hardware profile and selected model.' 6
        Ensure-AgentPortRuntimeDirs
        $root=[string]$script:Config.textgen_root
        if($root -match '\s'){ throw "TextGen's runtime folder cannot contain spaces. Change it in Settings: $root" }
        if(-not (Test-Path -LiteralPath $m.FullPath)){ throw "Selected GGUF no longer exists: $($m.FullPath)" }
        if($m.HelperFiles -and $m.HelperFiles.Count -gt 0){ Set-Log ('Helper file detected for multimodal GGUF: '+[IO.Path]::GetFileName($m.HelperFiles[0])) 'ok' }

        Set-LaunchPhase 2 'Writing runtime profile' 'Synchronising model, context, cache and Harness settings.' 14
        $script:Config.last_model=$m.RelPath
        $script:Config.last_context=$ctxLabel
        $script:Config.cache_type=$cache
        $script:Config.offload_mode=$offload
        $script:Config.speculative_mode=$spec
        $script:Config.draft_mtp=($spec -ne 'Off')
        $script:Config.max_tokens=$max
        $script:Config.active_model=$m.RelPath
        $script:Config.active_context_tokens=$ctx
        $script:Config.active_offload_mode=$offload
        Save-Config
        Prepare-IsolatedHarnessSkills
        Write-TextGenFlags $m.RelPath $ctx $cache $offload $spec
        Update-HarnessSettings $m.RelPath $m.Name $ctx $max
        $script:PendingModel=$m.RelPath
        $script:PendingContext=$ctx

        Set-LaunchPhase 3 'Preparing local runtime' 'Stopping stale local processes and checking the TextGen installation.' 21
        Kill-Stack
        Start-Sleep -Milliseconds 250

        if(Test-TextGenInstalled){
            Set-LaunchPhase 4 'Starting TextGen' 'Launching the isolated TextGen Python/CUDA runtime.' 42
            Start-TextGen
            $script:LaunchState='wait_textgen'
            $script:LaunchDeadline=(Get-Date).AddMinutes(5)
            $PrimaryButton.Content='Starting TextGen...'
            Set-LaunchPhase 4 'Starting TextGen' 'Process launched. Waiting for the API to bind to 127.0.0.1:5100.' 52
            Set-Log ('Starting '+$m.Name+' | '+('{0:N0}' -f $ctx)+' tokens | '+$offload)
        } else {
            $answer=[System.Windows.MessageBox]::Show(
                "AgentPort needs to prepare the local TextGen runtime once.`n`nIt will download an isolated Python/CUDA environment and may use around 10 GB of disk space. No separate Python, Git or CUDA install is required.`n`nContinue?",
                'First-run local runtime setup',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Information
            )
            if($answer -ne [System.Windows.MessageBoxResult]::Yes){ throw 'First-run setup was cancelled.' }
            Begin-TextGenBootstrap
        }
    }catch{
        $script:LaunchState='idle'
        $PrimaryButton.IsEnabled=$true
        $PrimaryButton.Content='Apply & Start'
        Set-LaunchPhase ([math]::Max(1,$script:LaunchPhase)) 'Startup failed' $_.Exception.Message $LaunchProgress.Value 'error'
        Set-Log $_.Exception.Message 'error'
        [System.Windows.MessageBox]::Show($_.Exception.Message,'Launch failed')|Out-Null
    }
}

function Poll-Launch {
    if($script:LaunchState -eq 'install_textgen'){
        if((Get-Date) -gt $script:LaunchDeadline){
            try{ if($script:BootstrapProcess -and -not $script:BootstrapProcess.HasExited){ $script:BootstrapProcess.Kill() } }catch{}
            $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
            Set-LaunchPhase 3 'TextGen installation timed out' ('Open Runtimes to inspect '+$script:BootstrapLog) $LaunchProgress.Value 'error'
            Set-Log 'First-run TextGen setup timed out. Open the Runtimes page to inspect the install log.' 'error'
            return
        }
        if($script:BootstrapLog -and (Test-Path -LiteralPath $script:BootstrapLog)){
            try{
                $tailLines=@(Get-Content -LiteralPath $script:BootstrapLog -Tail 80 -ErrorAction SilentlyContinue)
                $tail=$tailLines | Select-Object -Last 1
                $joined=$tailLines -join "`n"
                $pct=32
                $title='Installing TextGen runtime'
                if($joined -match 'Downloading Miniforge'){ $pct=34; $title='Downloading Miniforge' }
                if($joined -match 'checksum verification.*passed'){ $pct=38; $title='Verifying runtime download' }
                if($joined -match 'Installing Miniforge'){ $pct=42; $title='Installing Miniforge' }
                if($joined -match 'create .*python=|environment creation|Packages to install'){ $pct=47; $title='Creating Python environment' }
                if($joined -match 'Installing PyTorch'){ $pct=54; $title='Installing GPU runtime' }
                if($joined -match 'Installing webui requirements|pip install -r'){ $pct=62; $title='Installing TextGen packages' }
                if($joined -match 'Will now exit due to LAUNCH_AFTER_INSTALL'){ $pct=68; $title='Finalising TextGen install' }
                Set-LaunchPhase 3 $title ([string]$tail) $pct
                if($tail){ $StatusText.Text=([string]$tail) }
            }catch{}
        }
        if($script:BootstrapProcess){
            $script:BootstrapProcess.Refresh()
            if($script:BootstrapProcess.HasExited){
                $code=$script:BootstrapProcess.ExitCode
                $script:BootstrapProcess=$null
                if($code -ne 0 -or -not (Test-TextGenInstalled)){
                    $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
                    $detail=Get-RecentLogText $script:BootstrapLog 8
                    if(-not $detail){$detail=('Installer exited with code '+$code+'.')}
                    Set-LaunchPhase 3 'TextGen installation failed' $detail $LaunchProgress.Value 'error'
                    Set-Log ('First-run TextGen setup failed (exit '+$code+'). See '+$script:BootstrapLog) 'error'
                    return
                }
                if($script:InstallOnlyMode){
                    $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'; $script:InstallOnlyMode=$false
                    Set-LaunchPhase 3 'TextGen installed' 'TextGen is installed and ready. Choose a model and press Apply & Start.' 100 'ok'
                    Set-Log 'TextGen runtime installed and ready.' 'ok'
                    Refresh-InstallStatus
                    return
                }
                try{
                    Set-LaunchPhase 4 'Starting TextGen' 'Installation complete. Launching the selected model runtime.' 72
                    Write-TextGenFlags $script:PendingModel $script:PendingContext ([string]$script:Config.cache_type) ([string]$script:Config.offload_mode) ([string]$script:Config.speculative_mode)
                    Start-TextGen
                    $script:LaunchState='wait_textgen'
                    $script:LaunchDeadline=(Get-Date).AddMinutes(5)
                    $PrimaryButton.Content='Starting TextGen...'
                    Set-LaunchPhase 4 'Starting TextGen' 'Waiting for API :5100.' 76
                    Set-Log 'Local runtime installed. Starting the selected model...' 'ok'
                }catch{
                    $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
                    Set-LaunchPhase 4 'TextGen launch failed' $_.Exception.Message $LaunchProgress.Value 'error'
                    Set-Log $_.Exception.Message 'error'
                }
            }
        }
    } elseif($script:LaunchState -eq 'wait_textgen'){
        if($script:TextGenProcess){
            try{
                $script:TextGenProcess.Refresh()
                if($script:TextGenProcess.HasExited -and -not (Test-Port 5100)){
                    $root=[string]$script:Config.textgen_root
                    $err=Get-RecentLogText (Join-Path $root 'logs\textgen.err.log') 10
                    $out=Get-RecentLogText (Join-Path $root 'logs\textgen.out.log') 6
                    $detail=if($err){$err}elseif($out){$out}else{('TextGen process exited with code '+$script:TextGenProcess.ExitCode+'.')}
                    $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
                    Set-LaunchPhase 4 'TextGen exited before API startup' $detail $LaunchProgress.Value 'error'
                    Set-Log ('TextGen exited before opening port 5100. '+$detail) 'error'
                    return
                }
            }catch{}
        }
        if((Get-Date) -gt $script:LaunchDeadline){
            $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
            $root=[string]$script:Config.textgen_root
            $detail=Get-RecentLogText (Join-Path $root 'logs\textgen.err.log') 10
            if(-not $detail){$detail='TextGen did not open API port 5100 within five minutes.'}
            Set-LaunchPhase 4 'TextGen startup timed out' $detail $LaunchProgress.Value 'error'
            Set-Log 'TextGen timed out. Open Runtimes for the exact error log.' 'error'
            return
        }
        if(Test-Port 5100){
            Set-LaunchPhase 5 'Verifying model' 'TextGen API is online. Confirming the selected GGUF is loaded.' 84
            $loaded=Get-LoadedModel
            if(Test-ModelMatch $script:PendingModel $loaded){
                try{
                    Set-LaunchPhase 6 'Starting Harness' 'Model verified. Starting the agent Harness and connecting it to TextGen.' 92
                    Start-Harness
                    $script:LaunchState='wait_harness'
                    $script:LaunchDeadline=(Get-Date).AddSeconds(120)
                    $PrimaryButton.Content='Starting Harness...'
                    Set-Log ('TextGen verified: '+[IO.Path]::GetFileName($loaded)+' | starting Harness') 'ok'
                }catch{
                    $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
                    Set-LaunchPhase 6 'Harness launch failed' $_.Exception.Message $LaunchProgress.Value 'error'
                    Set-Log $_.Exception.Message 'error'
                }
            } elseif($loaded) {
                $LaunchDetailText.Text=('API online; waiting for selected model. TextGen currently reports: '+[IO.Path]::GetFileName($loaded))
            }
        }
    } elseif($script:LaunchState -eq 'wait_harness'){
        if((Get-Date) -gt $script:LaunchDeadline){
            $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply & Start'
            $root=[string]$script:Config.textgen_root
            $detail=Get-RecentLogText (Join-Path $root 'logs\harness.err.log') 10
            if(-not $detail){$detail='Harness did not open port 3080 within two minutes.'}
            Set-LaunchPhase 6 'Harness startup timed out' $detail $LaunchProgress.Value 'error'
            Set-Log 'Harness timed out. Open Runtimes for the exact error log.' 'error'
            return
        }
        if(Test-Port 3080){
            $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; $PrimaryButton.Content='Apply / Switch'
            Set-LaunchPhase 7 'Ready' 'TextGen, the selected model and Harness are synchronised.' 100 'ok'
            Set-Log 'TextGen + Harness are synchronised and ready.' 'ok'
            Start-Process 'http://127.0.0.1:3080'
        }
    }
}

function Offload-Model {
    if(-not (Test-Port 5100)){ Set-Log 'TextGen is offline. Nothing to offload.'; return }
    try{ Invoke-TextGenApi '/v1/internal/model/unload' 'POST' @{} 20 | Out-Null; $script:Config.active_model=''; Save-Config; Set-Log 'Model offloaded. TextGen stays online.' 'ok' }catch{ Set-Log ('Unload API failed: '+$_.Exception.Message) 'error' }
}

function Refresh-Runtime {
    Refresh-InstallStatus
    if($script:StatusBusy){return}; $script:StatusBusy=$true
    try{
        $tg=Test-Port 5100; $ds=Test-Port 3080
        $TextGenStatus.Text=':5100'
        $HarnessStatus.Text=':3080'
        $TextGenDot.Fill = if($tg){'#51E57A'}else{'#4B4B56'}
        $HarnessDot.Fill = if($ds){'#51E57A'}else{'#4B4B56'}
        $TextGenOnline.Text = if($tg){'Online'}else{'Offline'}
        $HarnessOnline.Text = if($ds){'Online'}else{'Offline'}
        $TextGenOnline.Foreground = if($tg){'#51E57A'}else{'#70707C'}
        $HarnessOnline.Foreground = if($ds){'#51E57A'}else{'#70707C'}
        if($tg){
            $loaded=Get-LoadedModel
            if($loaded){
                $RuntimeModel.Text=[IO.Path]::GetFileName($loaded)
                if(Test-ModelMatch ([string]$script:Config.active_model) $loaded){
                    $ctx=[int]$script:Config.active_context_tokens
                    $mode=[string]$script:Config.active_offload_mode
                    $RuntimeContext.Text=('{0:N0} token context' -f $ctx)
                    $RuntimeOffload.Text=$mode
                } else {
                    $RuntimeContext.Text='Context unknown'
                    $RuntimeOffload.Text='Loaded externally'
                }
                $RuntimeApi.Text='TextGen API :5100'
                $RuntimeState.Text='Ready'; $RuntimeState.Foreground='#51E57A'; $RuntimeStateDot.Fill='#51E57A'
                if($script:LaunchState -eq 'idle'){$PrimaryButton.Content='Apply / Switch'}
            } else {
                $RuntimeModel.Text='No model loaded'; $RuntimeContext.Text='TextGen is online'; $RuntimeOffload.Text='Model offloaded'; $RuntimeApi.Text='TextGen API :5100'
                $RuntimeState.Text='Offloaded'; $RuntimeState.Foreground='#A894FF'; $RuntimeStateDot.Fill='#8A6DFF'
                if($script:LaunchState -eq 'idle'){$PrimaryButton.Content='Load selected model'}
            }
        } else {
            $RuntimeModel.Text='No model loaded'; $RuntimeContext.Text='Choose a model'; $RuntimeOffload.Text='Runtime offline'; $RuntimeApi.Text='TextGen API :5100'
            $RuntimeState.Text='Offline'; $RuntimeState.Foreground='#858596'; $RuntimeStateDot.Fill='#4B4B56'
            if($script:LaunchState -eq 'idle'){$PrimaryButton.Content='Apply & Start'}
        }
    } finally { $script:StatusBusy=$false }
}


function Refresh-SkillsPanel {
    if(-not $SkillsListPanel){ return }
    $SkillsListPanel.Children.Clear()
    $root=[string]$script:Config.harness_skills_root
    if(-not(Test-Path $root)){ New-Item -ItemType Directory -Force -Path $root | Out-Null }
    $items=@(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    if($items.Count -eq 0){
        $t=New-Object System.Windows.Controls.TextBlock
        $t.Text='No Harness-only skills installed yet.'; $t.Foreground='#858596'; $t.FontSize=12; $t.Margin='0,4,0,0'
        [void]$SkillsListPanel.Children.Add($t)
        return
    }
    foreach($item in $items){
        $b=New-Object System.Windows.Controls.Border
        $b.Background='#0E1117'; $b.BorderBrush='#202630'; $b.BorderThickness='1'; $b.CornerRadius='14'; $b.Padding='14'; $b.Margin='0,0,0,8'
        $g=New-Object System.Windows.Controls.Grid
        $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='*'}))
        $g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))
        $n=New-Object System.Windows.Controls.TextBlock; $n.Text=$item.Name; $n.Foreground='#F2F2F4'; $n.FontSize=13; $n.FontWeight='SemiBold'; $n.VerticalAlignment='Center'
        [System.Windows.Controls.Grid]::SetColumn($n,0); [void]$g.Children.Add($n)
        $p=New-Object System.Windows.Controls.TextBlock; $p.Text='Harness only'; $p.Foreground='#9A86FF'; $p.FontSize=11; $p.VerticalAlignment='Center'
        [System.Windows.Controls.Grid]::SetColumn($p,1); [void]$g.Children.Add($p)
        $b.Child=$g; [void]$SkillsListPanel.Children.Add($b)
    }
}

function Load-AgentPortProfiles {
    $h=[ordered]@{}
    if(Test-Path -LiteralPath $script:ProfilesFile){
        try{
            $o=Get-Content -LiteralPath $script:ProfilesFile -Raw | ConvertFrom-Json
            foreach($p in $o.PSObject.Properties){ $h[$p.Name]=$p.Value }
        }catch{}
    }
    return $h
}
function Save-AgentPortProfiles($Profiles){ Ensure-ConfigDir; $Profiles | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ProfilesFile -Encoding UTF8 }
function Save-CurrentProfile {
    try{ Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue }catch{}
    $name=[Microsoft.VisualBasic.Interaction]::InputBox('Name this runtime profile:','Save AgentPort profile','My profile')
    if([string]::IsNullOrWhiteSpace($name)){ return }
    $m=Get-SelectedModel; if($null -eq $m){ return }
    $profiles=Load-AgentPortProfiles
    $profiles[$name]=[ordered]@{
        model=$m.RelPath; context=[string]$ContextCombo.SelectedItem; offload=[string]$OffloadCombo.SelectedItem; cache=[string]$CacheCombo.SelectedItem; speculative=[string]$SpecCombo.SelectedItem; max_tokens=[string]$MaxTokensCombo.SelectedItem
    }
    Save-AgentPortProfiles $profiles
    Set-Log ('Saved profile: '+$name) 'ok'
}
function Load-AgentPortProfile($Profile){
    if($null -eq $Profile){return}
    if($Profile.model){
        for($i=0;$i -lt $script:Models.Count;$i++){ if($script:Models[$i].RelPath -eq [string]$Profile.model){$ModelCombo.SelectedIndex=$i;break} }
    }
    if($Profile.context){$ContextCombo.SelectedItem=[string]$Profile.context}
    if($Profile.offload){$OffloadCombo.SelectedItem=[string]$Profile.offload}
    if($Profile.cache){$CacheCombo.SelectedItem=[string]$Profile.cache}
    if($Profile.speculative){$SpecCombo.SelectedItem=[string]$Profile.speculative}
    if($Profile.max_tokens){$MaxTokensCombo.SelectedItem=[string]$Profile.max_tokens}
    Update-MemoryFit
}
function Show-ProfilesMenu {
    $menu=New-Object System.Windows.Controls.ContextMenu
    $save=New-Object System.Windows.Controls.MenuItem; $save.Header='Save current profile...'; $save.Add_Click({Save-CurrentProfile}); [void]$menu.Items.Add($save)
    $profiles=Load-AgentPortProfiles
    if($profiles.Count -gt 0){ [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator)) }
    foreach($name in $profiles.Keys){
        $item=New-Object System.Windows.Controls.MenuItem; $item.Header=$name; $item.Tag=$profiles[$name]
        $item.Add_Click({param($s,$e) Load-AgentPortProfile $s.Tag; Set-Log ('Loaded profile: '+[string]$s.Header) 'ok'})
        [void]$menu.Items.Add($item)
    }
    $SavedProfilesButton.ContextMenu=$menu; $menu.PlacementTarget=$SavedProfilesButton; $menu.IsOpen=$true
}
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AgentPort" Width="1440" Height="930" MinWidth="1160" MinHeight="760"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanResizeWithGrip"
        FontFamily="DM Sans, Segoe UI" TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType">
  <Window.Resources>
    <SolidColorBrush x:Key="AppBg" Color="#080B10"/>
    <SolidColorBrush x:Key="SidebarBg" Color="#090C11"/>
    <SolidColorBrush x:Key="Card" Color="#0D1117"/>
    <SolidColorBrush x:Key="CardHover" Color="#121721"/>
    <SolidColorBrush x:Key="Field" Color="#0B0F14"/>
    <SolidColorBrush x:Key="Line" Color="#242A33"/>
    <SolidColorBrush x:Key="Text" Color="#F5F5F6"/>
    <SolidColorBrush x:Key="Muted" Color="#9A9AA4"/>
    <SolidColorBrush x:Key="Purple" Color="#7B61FF"/>
    <LinearGradientBrush x:Key="PurpleGradient" StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#4737C8" Offset="0"/><GradientStop Color="#7358FF" Offset="0.55"/><GradientStop Color="#4E3CC7" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="RuntimeGradient" StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#0D1117" Offset="0"/><GradientStop Color="#0D1117" Offset="0.62"/><GradientStop Color="#151438" Offset="1"/></LinearGradientBrush>

    <Style x:Key="ModernButton" TargetType="Button">
      <Setter Property="Foreground" Value="#F3F3F5"/><Setter Property="Background" Value="#0F141A"/><Setter Property="BorderBrush" Value="#282F39"/><Setter Property="BorderThickness" Value="1"/><Setter Property="FontFamily" Value="DM Sans, Segoe UI"/><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="Medium"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="18,11"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="13" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#151B23"/><Setter TargetName="B" Property="BorderBrush" Value="#343C48"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.78"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.38"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="PrimaryButtonStyle" TargetType="Button" BasedOn="{StaticResource ModernButton}"><Setter Property="Background" Value="{StaticResource PurpleGradient}"/><Setter Property="BorderBrush" Value="#806EFF"/><Setter Property="Foreground" Value="White"/><Setter Property="FontSize" Value="18"/><Setter Property="FontWeight" Value="Medium"/><Setter Property="Padding" Value="20,15"/></Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}"><Setter Property="Foreground" Value="#FF9D9D"/><Setter Property="Background" Value="#1A1014"/><Setter Property="BorderBrush" Value="#3A2028"/></Style>
    <Style x:Key="NavButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
      <Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Padding" Value="18,13"/><Setter Property="Margin" Value="0,0,0,8"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="FontSize" Value="14"/><Setter Property="Foreground" Value="#B8B8C0"/>
      <Style.Triggers><Trigger Property="Tag" Value="active"><Setter Property="Background" Value="#17152B"/><Setter Property="BorderBrush" Value="#4D3DB4"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></Style.Triggers>
    </Style>
    <Style x:Key="QuickButton" TargetType="Button" BasedOn="{StaticResource ModernButton}"><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Padding" Value="16,10"/><Setter Property="Background" Value="#0D1117"/><Setter Property="MinHeight" Value="60"/></Style>
    <Style x:Key="IconButton" TargetType="Button" BasedOn="{StaticResource ModernButton}"><Setter Property="Padding" Value="0"/><Setter Property="Width" Value="30"/><Setter Property="Height" Value="24"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="FontSize" Value="13"/></Style>

    <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="#F2F2F4"/><Setter Property="Background" Value="#0C1016"/><Setter Property="Padding" Value="12,9"/><Style.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="#18152D"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#211B43"/></Trigger></Style.Triggers></Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="Background" Value="#0B0F14"/><Setter Property="BorderBrush" Value="#2A3039"/><Setter Property="BorderThickness" Value="1"/><Setter Property="FontFamily" Value="DM Sans, Segoe UI"/><Setter Property="FontSize" Value="13"/><Setter Property="Height" Value="46"/><Setter Property="Padding" Value="14,0,40,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><Border x:Name="Outer" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12"/><ToggleButton Focusable="False" ClickMode="Press" Background="Transparent" BorderThickness="0" HorizontalAlignment="Stretch" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent"><TextBlock Text="&#x2304;" Foreground="#A7A7B0" FontSize="18" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,15,7"/></Border></ControlTemplate></ToggleButton.Template></ToggleButton><ContentPresenter IsHitTestVisible="False" Margin="14,0,42,0" VerticalAlignment="Center" HorizontalAlignment="Left" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/><Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade"><Border Background="#0C1016" BorderBrush="#303744" BorderThickness="1" CornerRadius="12" Margin="0,6,0,0" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"><ScrollViewer MaxHeight="280" Margin="4"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Outer" Property="BorderBrush" Value="#3A4350"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Outer" Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="#0B0F14"/><Setter Property="Foreground" Value="#F4F4F6"/><Setter Property="BorderBrush" Value="#2A3039"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="14,11"/><Setter Property="FontFamily" Value="DM Sans, Segoe UI"/><Setter Property="FontSize" Value="13"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12" Padding="{TemplateBinding Padding}"><ScrollViewer x:Name="PART_ContentHost"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ProgressBar"><Setter Property="Height" Value="7"/><Setter Property="Background" Value="#1B2028"/><Setter Property="Foreground" Value="#7B61FF"/><Setter Property="BorderThickness" Value="0"/></Style>
  </Window.Resources>

  <Border CornerRadius="28" Background="{StaticResource AppBg}" BorderBrush="#252B34" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="*"/></Grid.RowDefinitions>

      <Border x:Name="TitleBar" Grid.Row="0" Background="#090C11" CornerRadius="28,28,0,0" BorderBrush="#1D232B" BorderThickness="0,0,0,1">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border x:Name="DragArea" Grid.Column="0" Background="Transparent"><TextBlock Text="&#x2807;  Drag window" Foreground="#5F606A" FontSize="10" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,10,0">
            <Button x:Name="MinButton" Content="-" Style="{StaticResource IconButton}"/>
            <Button x:Name="MaxButton" Content="&#x25A1;" Style="{StaticResource IconButton}" Margin="2,0,0,0"/>
            <Button x:Name="CloseButton" Content="&#x2715;" Style="{StaticResource IconButton}" Margin="2,0,0,0"/>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="1"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="{StaticResource SidebarBg}" CornerRadius="0,0,0,28">
          <Grid Margin="26,0,20,22">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid Grid.Row="0" Margin="7,18,7,24" Height="120">
              <Image x:Name="BrandLogo" Width="156" Height="120" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality" SnapsToDevicePixels="True"/>
            </Grid>
            <StackPanel Grid.Row="1">
              <Button x:Name="NavHome" Style="{StaticResource NavButton}" Tag="active"><StackPanel Orientation="Horizontal"><TextBlock Text="&#x2302;" FontSize="20" Width="32"/><TextBlock Text="Home" VerticalAlignment="Center"/></StackPanel></Button>
              <Button x:Name="NavModels" Style="{StaticResource NavButton}" Tag="inactive"><StackPanel Orientation="Horizontal"><TextBlock Text="&#x25C7;" FontSize="19" Width="32"/><TextBlock Text="Models" VerticalAlignment="Center"/></StackPanel></Button>
              <Button x:Name="NavRuntimes" Style="{StaticResource NavButton}" Tag="inactive"><StackPanel Orientation="Horizontal"><TextBlock Text="&gt;_" FontFamily="Cascadia Mono, Consolas" FontSize="15" Width="32"/><TextBlock Text="Runtimes" VerticalAlignment="Center"/></StackPanel></Button>
              <Button x:Name="NavSkills" Style="{StaticResource NavButton}" Tag="inactive"><StackPanel Orientation="Horizontal"><TextBlock Text="&#x2261;" FontSize="22" Width="32"/><TextBlock Text="Skills" VerticalAlignment="Center"/></StackPanel></Button>
              <Button x:Name="NavSettings" Style="{StaticResource NavButton}" Tag="inactive"><StackPanel Orientation="Horizontal"><TextBlock Text="&#x2699;" FontSize="19" Width="32"/><TextBlock Text="Settings" VerticalAlignment="Center"/></StackPanel></Button>
            </StackPanel>

            <StackPanel Grid.Row="3">
              <Border Background="#0D1117" BorderBrush="#262D36" BorderThickness="1" CornerRadius="14" Padding="15" Margin="0,0,0,12">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,13"><Ellipse Width="8" Height="8" Fill="#8069FF" Margin="0,0,9,0"/><TextBlock Text="Runtimes Active" Foreground="#B5B5BE" FontSize="12"/></StackPanel>
                  <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="TextGen" Foreground="#D6D6DB" FontSize="12"/><TextBlock x:Name="TextGenStatus" Grid.Column="1" Text=":5100" Foreground="#917CFF" FontSize="12"/><Ellipse x:Name="TextGenDot" Grid.Column="3" Width="8" Height="8" Fill="#4B4B56" VerticalAlignment="Center"/><TextBlock x:Name="TextGenOnline" Visibility="Collapsed"/></Grid>
                  <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Harness" Foreground="#D6D6DB" FontSize="12"/><TextBlock x:Name="HarnessStatus" Grid.Column="1" Text=":3080" Foreground="#917CFF" FontSize="12"/><Ellipse x:Name="HarnessDot" Grid.Column="3" Width="8" Height="8" Fill="#4B4B56" VerticalAlignment="Center"/><TextBlock x:Name="HarnessOnline" Visibility="Collapsed"/></Grid>
                </StackPanel>
              </Border>
              <Button x:Name="SidebarOffloadButton" Style="{StaticResource ModernButton}" Margin="0,0,0,64"><StackPanel Orientation="Horizontal"><TextBlock Text="&#x21E7;" FontSize="17" Width="28"/><TextBlock Text="Offload Model"/></StackPanel></Button>
              <Grid><TextBlock Text="v1.6.2" Foreground="#6D6E78" FontSize="10"/><StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Ellipse Width="7" Height="7" Fill="#51E57A" Margin="0,0,7,0"/><TextBlock Text="Up to date" Foreground="#85858F" FontSize="10"/></StackPanel></Grid>
            </StackPanel>
          </Grid>
        </Border>
        <Border Grid.Column="1" Background="#20262E"/>

        <Grid Grid.Column="2" Margin="36,0,36,14">
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid Grid.Row="0" Margin="8,8,0,9">
            <StackPanel><StackPanel Orientation="Horizontal"><TextBlock Text="Hi, Elliot" Foreground="#F6F6F7" FontSize="29" FontWeight="SemiBold"/><TextBlock Text="&#x1F44B;" FontFamily="Segoe UI Emoji" FontSize="25" Margin="9,0,0,0"/></StackPanel><TextBlock Text="Ready to run your local models." Foreground="#A0A0A8" FontSize="14" Margin="0,3,0,0"/></StackPanel>
          </Grid>

          <Grid Grid.Row="1">
            <ScrollViewer x:Name="HomePage" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel>
                <Border Background="{StaticResource RuntimeGradient}" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="28,16" Margin="0,0,0,10">
                  <Grid Height="150"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="300"/></Grid.ColumnDefinitions>
                    <StackPanel><TextBlock Text="Current Runtime" Foreground="#D4D4D9" FontSize="13"/><TextBlock x:Name="RuntimeModel" Text="No model loaded" Foreground="#F8F8F9" FontSize="29" FontWeight="SemiBold" Margin="0,10,0,18" TextTrimming="CharacterEllipsis"/><StackPanel Orientation="Horizontal"><Border Background="#0B0F14" BorderBrush="#282F39" BorderThickness="1" CornerRadius="10" Padding="12,8" Margin="0,0,10,0"><TextBlock x:Name="RuntimeContext" Text="Choose a model" Foreground="#D5D5DA" FontSize="11"/></Border><Border Background="#0B0F14" BorderBrush="#282F39" BorderThickness="1" CornerRadius="10" Padding="12,8" Margin="0,0,10,0"><TextBlock x:Name="RuntimeOffload" Text="Runtime offline" Foreground="#D5D5DA" FontSize="11"/></Border><Border Background="#0B0F14" BorderBrush="#282F39" BorderThickness="1" CornerRadius="10" Padding="12,8"><TextBlock x:Name="RuntimeApi" Text="TextGen API :5100" Foreground="#D5D5DA" FontSize="11"/></Border></StackPanel></StackPanel>
                    <Grid Grid.Column="1"><Canvas Width="270" Height="150" HorizontalAlignment="Right"><Ellipse Width="235" Height="75" Stroke="#6554D8" StrokeThickness="1" Opacity="0.42" Canvas.Left="16" Canvas.Top="40"/><Ellipse Width="175" Height="52" Stroke="#6554D8" StrokeThickness="1" Opacity="0.42" Canvas.Left="46" Canvas.Top="51"/><Border Width="86" Height="86" CornerRadius="8" BorderBrush="#7B61FF" BorderThickness="1" Background="#0A0D12" Canvas.Left="91" Canvas.Top="27"><StackPanel VerticalAlignment="Center" HorizontalAlignment="Center"><Border Width="42" Height="1" Background="#7B61FF" Margin="0,0,0,10"/><Border Width="34" Height="1" Background="#7B61FF" Margin="0,0,0,10"/><Border Width="27" Height="1" Background="#7B61FF"/></StackPanel></Border></Canvas><Border Background="#0D1712" BorderBrush="#1C3928" BorderThickness="1" CornerRadius="10" Padding="11,7" HorizontalAlignment="Right" VerticalAlignment="Bottom"><StackPanel Orientation="Horizontal"><Ellipse x:Name="RuntimeStateDot" Width="8" Height="8" Fill="#4B4B56" Margin="0,0,8,0"/><TextBlock x:Name="RuntimeState" Text="Offline" Foreground="#858596" FontSize="11"/></StackPanel></Border></Grid>
                  </Grid>
                </Border>

                <Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="28,15" Margin="0,0,0,10">
                  <StackPanel>
                    <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="30"/><ColumnDefinition/><ColumnDefinition Width="30"/><ColumnDefinition/></Grid.ColumnDefinitions>
                      <StackPanel><TextBlock Text="Model" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="ModelCombo"/><Button x:Name="BrowseModelsButton" Content="Browse Models" Style="{StaticResource ModernButton}" Margin="0,8,0,0"/></StackPanel>
                      <StackPanel Grid.Column="2"><TextBlock Text="Context Length" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="ContextCombo"/><TextBlock Text="Auto-detects your VRAM" Foreground="#898993" FontSize="11" Margin="0,8,0,0"/></StackPanel>
                      <StackPanel Grid.Column="4"><TextBlock Text="GPU Offload" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="OffloadCombo"/><TextBlock Text="Best balance of speed &amp; memory" Foreground="#898993" FontSize="11" Margin="0,8,0,0"/></StackPanel>
                    </Grid>
                    <Border Height="1" Background="#20262E" Margin="0,12,0,12"/>
                    <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="30"/><ColumnDefinition/><ColumnDefinition Width="30"/><ColumnDefinition/></Grid.ColumnDefinitions>
                      <StackPanel><TextBlock Text="KV Cache" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="CacheCombo"/><TextBlock Text="Let system optimise" Foreground="#898993" FontSize="11" Margin="0,8,0,0"/></StackPanel>
                      <StackPanel Grid.Column="2"><TextBlock Text="Speculative Decoding" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="SpecCombo"/><TextBlock Text="Balance speed and stability" Foreground="#898993" FontSize="11" Margin="0,8,0,0"/></StackPanel>
                      <StackPanel Grid.Column="4"><TextBlock Text="Max New Tokens" Foreground="#E8E8EB" FontSize="13" Margin="0,0,0,10"/><ComboBox x:Name="MaxTokensCombo"/><TextBlock Text="For responses &amp; generations" Foreground="#898993" FontSize="11" Margin="0,8,0,0"/></StackPanel>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="20,12" Margin="0,0,0,10">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/><ColumnDefinition Width="20"/><ColumnDefinition Width="270"/></Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                      <Grid><TextBlock Text="GPU VRAM fit" Foreground="#BDBDC5" FontSize="11"/><TextBlock x:Name="HomeVramText" Text="-" Foreground="#F3F3F5" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Right"/></Grid>
                      <ProgressBar x:Name="HomeVramBar" Maximum="100" Margin="0,9,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2">
                      <Grid><TextBlock Text="System RAM" Foreground="#BDBDC5" FontSize="11"/><TextBlock x:Name="HomeRamText" Text="-" Foreground="#F3F3F5" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Right"/></Grid>
                      <ProgressBar x:Name="HomeRamBar" Maximum="100" Margin="0,9,0,0"/>
                    </StackPanel>
                    <Border Grid.Column="4" Background="#0A0E13" BorderBrush="#262D36" BorderThickness="1" CornerRadius="12" Padding="13,10">
                      <StackPanel>
                        <TextBlock x:Name="HomeFitStatus" Text="Checking hardware fit..." Foreground="#D7D7DC" FontSize="12" FontWeight="SemiBold"/>
                        <TextBlock x:Name="HomeMemorySummary" Text="Select a model and context." Foreground="#85858F" FontSize="10" Margin="0,3,0,0" TextWrapping="Wrap"/>
                      </StackPanel>
                    </Border>
                  </Grid>
                </Border>

                <Grid Margin="0,0,0,7"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="22"/><ColumnDefinition Width="250"/></Grid.ColumnDefinitions><Button x:Name="PrimaryButton" Grid.Column="0" Content="Apply &amp; Start" Style="{StaticResource PrimaryButtonStyle}"/><Button x:Name="SavedProfilesButton" Grid.Column="2" Content="Saved Profiles" Style="{StaticResource ModernButton}"/></Grid>
                <TextBlock x:Name="StatusText" Text="This will update settings and start TextGen &amp; Harness together." Foreground="#8E8E97" FontSize="11" HorizontalAlignment="Center" Margin="0,0,0,6"/>

                <Border x:Name="LaunchProgressCard" Visibility="Collapsed" Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="14" Padding="16,13" Margin="0,0,0,14">
                  <StackPanel>
                    <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="LaunchPhaseText" Text="Phase 1 of 7  ·  Preflight" Foreground="#F1F1F4" FontSize="12" FontWeight="SemiBold"/><TextBlock x:Name="LaunchPercentText" Grid.Column="1" Text="0%" Foreground="#A99BFF" FontSize="11" FontWeight="SemiBold"/></Grid>
                    <ProgressBar x:Name="LaunchProgress" Maximum="100" Value="0" Height="8" Margin="0,10,0,8"/>
                    <TextBlock x:Name="LaunchDetailText" Text="Checking runtime..." Foreground="#85858F" FontSize="10" TextWrapping="Wrap"/>
                  </StackPanel>
                </Border>

                <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
                  <Button x:Name="QuickHfButton" Grid.Column="0" Style="{StaticResource QuickButton}"><StackPanel><TextBlock Text="Hugging Face" Foreground="#F2F2F4" FontSize="12"/><TextBlock Text="Download models" Foreground="#7F808A" FontSize="10" Margin="0,4,0,0"/></StackPanel></Button>
                  <Button x:Name="QuickImportButton" Grid.Column="2" Style="{StaticResource QuickButton}"><StackPanel><TextBlock Text="Import GGUF" Foreground="#F2F2F4" FontSize="12"/><TextBlock Text="From file or folder" Foreground="#7F808A" FontSize="10" Margin="0,4,0,0"/></StackPanel></Button>
                  <Button x:Name="QuickModelsFolderButton" Grid.Column="4" Style="{StaticResource QuickButton}"><StackPanel><TextBlock Text="Open Model Folder" Foreground="#F2F2F4" FontSize="12"/><TextBlock Text="View in Explorer" Foreground="#7F808A" FontSize="10" Margin="0,4,0,0"/></StackPanel></Button>
                  <Button x:Name="QuickConfigFolderButton" Grid.Column="6" Style="{StaticResource QuickButton}"><StackPanel><TextBlock Text="Open Config Folder" Foreground="#F2F2F4" FontSize="12"/><TextBlock Text="View settings" Foreground="#7F808A" FontSize="10" Margin="0,4,0,0"/></StackPanel></Button>
                  <Button x:Name="QuickLogsButton" Grid.Column="8" Style="{StaticResource QuickButton}"><StackPanel><TextBlock Text="View Logs" Foreground="#F2F2F4" FontSize="12"/><TextBlock Text="Runtime logs" Foreground="#7F808A" FontSize="10" Margin="0,4,0,0"/></StackPanel></Button>
                </Grid>
              </StackPanel>
            </ScrollViewer>

            <ScrollViewer x:Name="ModelsPage" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <TextBlock Text="Models" Foreground="#F6F6F7" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="Install, import and manage GGUF models from one place." Foreground="#92929B" FontSize="13" Margin="0,4,0,20"/>
                <Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="24" Margin="0,0,0,14"><StackPanel><TextBlock Text="Install from Hugging Face" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Paste a repository URL or owner/repo ID." Foreground="#85858F" FontSize="11" Margin="0,4,0,14"/><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="RepoInput" Grid.Column="0" Height="46" Text="https://huggingface.co/empero-ai/Qwen3.8-27B-Ridge-GGUF"/><Button x:Name="InspectButton" Grid.Column="2" Content="Inspect files" Style="{StaticResource ModernButton}"/></Grid><TextBlock Text="Quant / GGUF file" Foreground="#B7B7BF" FontSize="11" Margin="0,15,0,7"/><ComboBox x:Name="RepoFileCombo"/><ProgressBar x:Name="DownloadProgress" Maximum="100" Margin="0,16,0,0"/><TextBlock x:Name="RepoStatus" Text="Inspect a repository to choose a GGUF file." Foreground="#85858F" FontSize="11" Margin="0,8,0,14"/><StackPanel Orientation="Horizontal"><Button x:Name="DownloadButton" Content="Download &amp; Install" Style="{StaticResource PrimaryButtonStyle}" FontSize="14" Padding="20,11"/><Button x:Name="ImportButton" Content="Import local GGUF" Style="{StaticResource ModernButton}" Margin="10,0,0,0"/></StackPanel></StackPanel></Border>
                <Grid Margin="0,6,0,12"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Installed models" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><Button x:Name="RefreshModelsButton" Grid.Column="1" Content="Refresh" Style="{StaticResource ModernButton}" Padding="14,8"/></Grid>
                <StackPanel x:Name="ModelListPanel"/>
              </StackPanel>
            </ScrollViewer>

            <ScrollViewer x:Name="RuntimesPage" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
              <StackPanel><TextBlock Text="Runtimes" Foreground="#F6F6F7" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="See what is running, how memory is being used, and inspect launcher activity." Foreground="#92929B" FontSize="13" Margin="0,4,0,20"/>
                <Grid Margin="0,0,0,14"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/></Grid.ColumnDefinitions><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="22"><StackPanel><TextBlock Text="GPU VRAM" Foreground="#BDBDC4" FontSize="12"/><TextBlock x:Name="VramText" Text="-" Foreground="#F4F4F6" FontSize="22" FontWeight="SemiBold" Margin="0,6,0,12"/><ProgressBar x:Name="VramBar" Maximum="100"/><TextBlock Text="Estimated model + cache footprint" Foreground="#777781" FontSize="10" Margin="0,8,0,0"/></StackPanel></Border><Border Grid.Column="2" Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="22"><StackPanel><TextBlock Text="System RAM" Foreground="#BDBDC4" FontSize="12"/><TextBlock x:Name="RamText" Text="-" Foreground="#F4F4F6" FontSize="22" FontWeight="SemiBold" Margin="0,6,0,12"/><ProgressBar x:Name="RamBar" Maximum="100"/><TextBlock x:Name="MemorySummary" Text="Estimating..." Foreground="#85858F" FontSize="10" Margin="0,8,0,0"/></StackPanel></Border></Grid>
                <Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="22"><StackPanel><Grid Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Activity log" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="RuntimeOpenUiButton" Content="Open Harness" Style="{StaticResource ModernButton}" Padding="12,7"/><Button x:Name="RuntimeOffloadButton" Content="Offload model" Style="{StaticResource ModernButton}" Padding="12,7" Margin="8,0,0,0"/><Button x:Name="StopButton" Content="Stop stack" Style="{StaticResource DangerButton}" Padding="12,7" Margin="8,0,0,0"/></StackPanel></Grid><TextBox x:Name="LogBox" Height="260" IsReadOnly="True" Background="#080B10" Foreground="#A8A8B0" BorderBrush="#252C35" FontFamily="Cascadia Mono, Consolas" FontSize="10" VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap"/></StackPanel></Border>
              </StackPanel>
            </ScrollViewer>

            <ScrollViewer x:Name="SkillsPage" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel><TextBlock Text="Skills" Foreground="#F6F6F7" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="Add skills that DeepSeek Harness can use. Keep them simple: each skill is a folder with a skill.md file and any helper files beside it." Foreground="#92929B" FontSize="13" Margin="0,4,0,20" TextWrapping="Wrap"/><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="24" Margin="0,0,0,14"><StackPanel><TextBlock Text="Harness-only skills folder" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><TextBlock x:Name="SkillsPathText" Foreground="#9B87FF" FontSize="12" Margin="0,8,0,14" TextWrapping="Wrap"/><WrapPanel><Button x:Name="AddSkillFolderButton" Content="Add skill folder" Style="{StaticResource ModernButton}" Margin="0,0,8,8"/><Button x:Name="ImportSkillZipButton" Content="Import skill ZIP" Style="{StaticResource ModernButton}" Margin="0,0,8,8"/><Button x:Name="CreateSkillButton" Content="Create blank skill" Style="{StaticResource ModernButton}" Margin="0,0,8,8"/><Button x:Name="OpenSkillsButton" Content="Open skills folder" Style="{StaticResource ModernButton}" Margin="0,0,8,8"/><Button x:Name="RefreshSkillsButton" Content="Refresh" Style="{StaticResource ModernButton}" Margin="0,0,8,8"/></WrapPanel></StackPanel></Border><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="20" Margin="0,0,0,14"><StackPanel><TextBlock Text="What works as a skill?" Foreground="#F3F3F5" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="Use a folder with a skill.md file that explains the action clearly. AgentPort copies these into DeepSeek Harness at launch so they stay separate from any other agent skills on your PC." Foreground="#92929B" FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/></StackPanel></Border><TextBlock Text="Installed Harness skills" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold" Margin="0,4,0,12"/><StackPanel x:Name="SkillsListPanel"/></StackPanel></ScrollViewer>

            <ScrollViewer x:Name="SettingsPage" Visibility="Collapsed" VerticalScrollBarVisibility="Auto"><StackPanel><TextBlock Text="Settings" Foreground="#F6F6F7" FontSize="28" FontWeight="SemiBold"/><TextBlock Text="Paths and maintenance. AgentPort can bootstrap its own local runtimes on a fresh Windows PC." Foreground="#92929B" FontSize="13" Margin="0,4,0,20"/><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="24" Margin="0,0,0,14"><StackPanel><TextBlock Text="Locations" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,16"/><Grid Margin="0,0,0,11"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Models" Foreground="#9A9AA4" VerticalAlignment="Center"/><TextBlock x:Name="ModelsPathText" Grid.Column="1" Foreground="#D1D1D6" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/><Button x:Name="ModelsPathButton" Grid.Column="2" Content="Change" Style="{StaticResource ModernButton}" Padding="13,7"/></Grid><Grid Margin="0,0,0,11"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="TextGen" Foreground="#9A9AA4" VerticalAlignment="Center"/><TextBlock x:Name="TextGenPathText" Grid.Column="1" Foreground="#D1D1D6" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/><Button x:Name="TextGenPathButton" Grid.Column="2" Content="Change" Style="{StaticResource ModernButton}" Padding="13,7"/></Grid><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="Harness workspace" Foreground="#9A9AA4" VerticalAlignment="Center"/><TextBlock x:Name="HarnessPathText" Grid.Column="1" Foreground="#D1D1D6" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/><Button x:Name="HarnessPathButton" Grid.Column="2" Content="Change" Style="{StaticResource ModernButton}" Padding="13,7"/></Grid></StackPanel></Border><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="24" Margin="0,0,0,14"><StackPanel><TextBlock Text="Setup checks" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="AgentPort needs TextGen for local GGUF inference and DeepSeek Harness for the agent interface. Use these buttons instead of guessing what is installed." Foreground="#92929B" FontSize="11" Margin="0,5,0,16" TextWrapping="Wrap"/><Grid Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="TextGen" Foreground="#D6D6DB" VerticalAlignment="Center"/><Ellipse x:Name="TextGenInstallDot" Grid.Column="1" Width="9" Height="9" Fill="#4B4B56" VerticalAlignment="Center" Margin="0,0,8,0"/><StackPanel Grid.Column="2"><TextBlock x:Name="TextGenInstallFlag" Text="Checking" Foreground="#8A8A94" FontWeight="SemiBold"/><TextBlock x:Name="TextGenInstallDetail" Text="" Foreground="#777788" FontSize="10" TextWrapping="Wrap"/></StackPanel><StackPanel Grid.Column="3" Orientation="Horizontal"><Button x:Name="InstallTextGenButton" Content="Install TextGen" Style="{StaticResource ModernButton}" Padding="13,7"/><Button x:Name="RepairTextGenButton" Content="Repair" Style="{StaticResource ModernButton}" Padding="13,7" Margin="8,0,0,0"/></StackPanel></Grid><Grid Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition Width="170"/><ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="DeepSeek Harness" Foreground="#D6D6DB" VerticalAlignment="Center"/><Ellipse x:Name="HarnessInstallDot" Grid.Column="1" Width="9" Height="9" Fill="#4B4B56" VerticalAlignment="Center" Margin="0,0,8,0"/><StackPanel Grid.Column="2"><TextBlock x:Name="HarnessInstallFlag" Text="Checking" Foreground="#8A8A94" FontWeight="SemiBold"/><TextBlock x:Name="HarnessInstallDetail" Text="" Foreground="#777788" FontSize="10" TextWrapping="Wrap"/></StackPanel><StackPanel Grid.Column="3" Orientation="Horizontal"><Button x:Name="InstallHarnessButton" Content="Install Harness" Style="{StaticResource ModernButton}" Padding="13,7"/><Button x:Name="RepairHarnessButton" Content="Repair" Style="{StaticResource ModernButton}" Padding="13,7" Margin="8,0,0,0"/></StackPanel></Grid><Button x:Name="ScanModelsButton" Content="Scan for models from AgentPort, TextGen, Ollama, LM Studio, Unsloth, Hugging Face, Jan and GPT4All" Style="{StaticResource ModernButton}" HorizontalAlignment="Left"/></StackPanel></Border><Border Background="#0D1117" BorderBrush="#2B313B" BorderThickness="1" CornerRadius="18" Padding="24" Margin="0,0,0,14"><StackPanel><TextBlock Text="Quick actions" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,15"/><StackPanel Orientation="Horizontal"><Button x:Name="OpenModelsButton" Content="Open models folder" Style="{StaticResource ModernButton}"/><Button x:Name="OpenConfigButton" Content="Open .dsh folder" Style="{StaticResource ModernButton}" Margin="8,0,0,0"/><Button x:Name="KillButton" Content="Kill local AI processes" Style="{StaticResource DangerButton}" Margin="8,0,0,0"/></StackPanel></StackPanel></Border><Border Background="#0D1117" BorderBrush="#33222A" BorderThickness="1" CornerRadius="18" Padding="24"><StackPanel><TextBlock Text="Component removal" Foreground="#F3F3F5" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Destructive actions are kept separate to prevent accidental clicks." Foreground="#7F808A" FontSize="11" Margin="0,4,0,14"/><StackPanel Orientation="Horizontal"><Button x:Name="UninstallTextGenButton" Content="Uninstall TextGen app files" Style="{StaticResource DangerButton}"/><Button x:Name="UninstallHarnessButton" Content="Uninstall DeepSeek Harness" Style="{StaticResource DangerButton}" Margin="8,0,0,0"/></StackPanel></StackPanel></Border></StackPanel></ScrollViewer>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [System.Windows.Markup.XamlReader]::Load($reader)
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $Window.MaxHeight = $wa.Height
    $Window.MaxWidth = $wa.Width
    if($Window.Height -gt $wa.Height){ $Window.Height = $wa.Height }
    if($Window.Width -gt $wa.Width){ $Window.Width = $wa.Width }
    $Window.WindowStartupLocation = 'CenterScreen'
} catch {}
try {
    $fsIcon = [IO.File]::OpenRead($script:IconPath)
    $decIcon = New-Object System.Windows.Media.Imaging.IconBitmapDecoder($fsIcon,[System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frameIcon = $decIcon.Frames | Where-Object { $_.PixelWidth -eq 64 } | Select-Object -First 1
    if(-not $frameIcon){ $frameIcon = $decIcon.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1 }
    $Window.Icon = $frameIcon
    $fsIcon.Dispose()
} catch {}
try {
    $dmDir=Ensure-DmSansFont
    if($dmDir){
        $fontBase=[Uri]::new(($dmDir.TrimEnd('\')+'\'),[UriKind]::Absolute)
        $Window.FontFamily=[System.Windows.Media.FontFamily]::new($fontBase,'./#DM Sans')
    }
} catch {}

$names = @('TextGenStatus','HarnessStatus','TextGenDot','HarnessDot','TextGenOnline','HarnessOnline','RuntimeModel','RuntimeContext','RuntimeOffload','RuntimeApi','RuntimeState','RuntimeStateDot','ModelCombo','ContextCombo','OffloadCombo','CacheCombo','SpecCombo','MaxTokensCombo','PrimaryButton','SavedProfilesButton','BrowseModelsButton','RepoInput','InspectButton','RepoFileCombo','DownloadProgress','RepoStatus','DownloadButton','ImportButton','ModelListPanel','RefreshModelsButton','VramBar','RamBar','VramText','RamText','MemorySummary','HomeVramBar','HomeRamBar','HomeVramText','HomeRamText','HomeFitStatus','HomeMemorySummary','BrandLogo','LogBox','RuntimeOpenUiButton','RuntimeOffloadButton','StopButton','SkillsPathText','OpenSkillsButton','RefreshSkillsButton','SkillsListPanel','ModelsPathText','TextGenPathText','HarnessPathText','ModelsPathButton','TextGenPathButton','HarnessPathButton','OpenModelsButton','OpenConfigButton','KillButton','UninstallTextGenButton','UninstallHarnessButton','HomePage','ModelsPage','RuntimesPage','SkillsPage','SettingsPage','NavHome','NavModels','NavRuntimes','NavSkills','NavSettings','StatusText','LaunchProgressCard','LaunchPhaseText','LaunchPercentText','LaunchProgress','LaunchDetailText','MinButton','MaxButton','CloseButton','TitleBar','DragArea','SidebarOffloadButton','QuickHfButton','QuickImportButton','QuickModelsFolderButton','QuickConfigFolderButton','QuickLogsButton','TextGenInstallFlag','TextGenInstallDetail','TextGenInstallDot','HarnessInstallFlag','HarnessInstallDetail','HarnessInstallDot','InstallTextGenButton','RepairTextGenButton','InstallHarnessButton','RepairHarnessButton','ScanModelsButton','AddSkillFolderButton','ImportSkillZipButton','CreateSkillButton')
foreach($n in $names){ Set-Variable -Name $n -Value $Window.FindName($n) -Scope Script }

# Use the approved AgentPort lockup itself in the sidebar rather than re-typesetting it.
try {
    $logoBytes=[Convert]::FromBase64String(($script:BrandLogoBase64 -replace '\s',''))
    $logoStream=New-Object IO.MemoryStream(,$logoBytes)
    $logoBitmap=New-Object System.Windows.Media.Imaging.BitmapImage
    $logoBitmap.BeginInit()
    $logoBitmap.CacheOption=[System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $logoBitmap.StreamSource=$logoStream
    $logoBitmap.EndInit()
    $logoBitmap.Freeze()
    $BrandLogo.Source=$logoBitmap
    $logoStream.Dispose()
} catch {}


foreach($k in $script:ContextPresets.Keys){ [void]$ContextCombo.Items.Add($k) }
foreach($k in $script:OffloadModes.Keys){ [void]$OffloadCombo.Items.Add($k) }
$ContextCombo.SelectedItem=[string]$script:Config.last_context; if($ContextCombo.SelectedIndex -lt 0){$ContextCombo.SelectedIndex=1}
$OffloadCombo.SelectedItem=[string]$script:Config.offload_mode; if($OffloadCombo.SelectedIndex -lt 0){$OffloadCombo.SelectedIndex=0}
$CacheCombo.Items.Clear(); [void]$CacheCombo.Items.Add('q4_0'); [void]$CacheCombo.Items.Add('fp16')
$CacheCombo.SelectedItem=[string]$script:Config.cache_type; if($CacheCombo.SelectedIndex -lt 0){$CacheCombo.SelectedIndex=0}
foreach($s in @('Off','Conservative','Medium','Aggressive')){[void]$SpecCombo.Items.Add($s)}
$specSaved=[string]$script:Config.speculative_mode; if(-not $specSaved){$specSaved=if([bool]$script:Config.draft_mtp){'Medium'}else{'Off'}}
$SpecCombo.SelectedItem=$specSaved; if($SpecCombo.SelectedIndex -lt 0){$SpecCombo.SelectedItem='Medium'}
foreach($v in @('1,024','2,048','4,096','8,192','16,384')){[void]$MaxTokensCombo.Items.Add($v)}
$maxSaved=('{0:N0}' -f [int]$script:Config.max_tokens); $MaxTokensCombo.SelectedItem=$maxSaved; if($MaxTokensCombo.SelectedIndex -lt 0){$MaxTokensCombo.SelectedItem='2,048'}

function Refresh-PathLabels {
    $ModelsPathText.Text=[string]$script:Config.models_root
    $TextGenPathText.Text=[string]$script:Config.textgen_root
    $HarnessPathText.Text=[string]$script:Config.harness_root
    $SkillsPathText.Text=[string]$script:Config.harness_skills_root
}
Refresh-PathLabels
Refresh-InstallStatus
Refresh-SkillsPanel

$DragArea.Add_MouseLeftButtonDown({
    if($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left){
        if($_.ClickCount -eq 2){ $Window.WindowState = if($Window.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'} }
        else { try{$Window.DragMove()}catch{} }
    }
})
$CloseButton.Add_Click({ $Window.Close() })
$MinButton.Add_Click({ $Window.WindowState='Minimized' })
$MaxButton.Add_Click({ $Window.WindowState = if($Window.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'} })

$NavHome.Add_Click({ Switch-Page 'Home' })
$NavModels.Add_Click({ Switch-Page 'Models' })
$NavRuntimes.Add_Click({ Switch-Page 'Runtimes' })
$NavSkills.Add_Click({ Switch-Page 'Skills' })
$NavSettings.Add_Click({ Switch-Page 'Settings' })

$ModelCombo.Add_SelectionChanged({ Update-MemoryFit })
$ContextCombo.Add_SelectionChanged({ Update-MemoryFit })
$CacheCombo.Add_SelectionChanged({ Update-MemoryFit })
$OffloadCombo.Add_SelectionChanged({ if($OffloadCombo.SelectedItem){ $StatusText.Text=$script:OffloadModes[[string]$OffloadCombo.SelectedItem].note } })
$PrimaryButton.Add_Click({ Start-UnifiedStack })
$SavedProfilesButton.Add_Click({ Show-ProfilesMenu })
$BrowseModelsButton.Add_Click({ Switch-Page 'Models' })
$SidebarOffloadButton.Add_Click({ Offload-Model })
$RuntimeOffloadButton.Add_Click({ Offload-Model })
$RuntimeOpenUiButton.Add_Click({ Start-Process 'http://127.0.0.1:3080' })
$StopButton.Add_Click({ Kill-Stack; $script:LaunchState='idle'; $PrimaryButton.IsEnabled=$true; Set-Log 'Stack stopped.' })

$QuickHfButton.Add_Click({ Switch-Page 'Models'; $RepoInput.Focus() | Out-Null })
$QuickImportButton.Add_Click({ Import-LocalGguf })
$QuickModelsFolderButton.Add_Click({ $p=[string]$script:Config.models_root; if(-not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null}; Start-Process explorer.exe $p })
$QuickConfigFolderButton.Add_Click({ Ensure-ConfigDir; Start-Process explorer.exe $script:ConfigDir })
$QuickLogsButton.Add_Click({ Switch-Page 'Runtimes' })

$InspectButton.Add_Click({ Inspect-HfRepo })
$DownloadButton.Add_Click({ Start-HfDownload })
$ImportButton.Add_Click({ Import-LocalGguf })
$RefreshModelsButton.Add_Click({ Refresh-Models; Set-Log 'Model list refreshed.' })
$RefreshSkillsButton.Add_Click({ Refresh-SkillsPanel; Set-Log 'Skills list refreshed.' })
if($AddSkillFolderButton){ $AddSkillFolderButton.Add_Click({ Add-SkillFolder }) }
if($ImportSkillZipButton){ $ImportSkillZipButton.Add_Click({ Import-SkillZip }) }
if($CreateSkillButton){ $CreateSkillButton.Add_Click({ Create-BlankSkill }) }

$ModelsPathButton.Add_Click({ $p=Choose-Folder ([string]$script:Config.models_root); if($p){$script:Config.models_root=$p;Save-Config;Refresh-PathLabels;Refresh-Models;Set-Log 'Models folder updated.' 'ok'} })
$TextGenPathButton.Add_Click({ $p=Choose-Folder ([string]$script:Config.textgen_root); if($p){$script:Config.textgen_root=$p;Save-Config;Refresh-PathLabels;Set-Log 'TextGen location updated.' 'ok'} })
$HarnessPathButton.Add_Click({ $p=Choose-Folder ([string]$script:Config.harness_root); if($p){$script:Config.harness_root=$p;Save-Config;Refresh-PathLabels;Set-Log 'Harness location updated.' 'ok'} })
$OpenSkillsButton.Add_Click({ $p=[string]$script:Config.harness_skills_root; if(-not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null}; Start-Process explorer.exe $p })
$OpenModelsButton.Add_Click({ $p=[string]$script:Config.models_root; if(-not(Test-Path $p)){New-Item -ItemType Directory -Force -Path $p|Out-Null}; Start-Process explorer.exe $p })
$OpenConfigButton.Add_Click({ Ensure-ConfigDir; Start-Process explorer.exe $script:ConfigDir })
$KillButton.Add_Click({ Kill-Stack; Set-Log 'All local TextGen / Harness processes terminated.' 'ok' })
$UninstallTextGenButton.Add_Click({
    $root=[string]$script:Config.textgen_root; $ans=[System.Windows.MessageBox]::Show("Remove TextGen application files from:`n`n$root`n`nThe user_data folder is preserved.",'Uninstall TextGen',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
    if($ans -eq [System.Windows.MessageBoxResult]::Yes){ Kill-Stack; Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object {$_.Name -ne 'user_data'} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Set-Log 'TextGen application files removed.' 'ok' }
})
if($InstallTextGenButton){ $InstallTextGenButton.Add_Click({ Start-TextGenInstallOnly $false }) }
if($RepairTextGenButton){ $RepairTextGenButton.Add_Click({ Start-TextGenInstallOnly $true }) }
if($InstallHarnessButton){ $InstallHarnessButton.Add_Click({ Install-DeepSeekHarness $false }) }
if($RepairHarnessButton){ $RepairHarnessButton.Add_Click({ Install-DeepSeekHarness $true }) }
if($ScanModelsButton){ $ScanModelsButton.Add_Click({ Scan-Models }) }
$UninstallHarnessButton.Add_Click({
    $root=[string]$script:Config.harness_root; $ans=[System.Windows.MessageBox]::Show("Permanently remove DeepSeek Harness from:`n`n$root ?",'Uninstall Harness',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
    if($ans -eq [System.Windows.MessageBoxResult]::Yes){ Kill-Stack; Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue; Set-Log 'DeepSeek Harness removed.' 'ok' }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Poll-Launch; Poll-Download; Refresh-Runtime })
$timer.Start()

Ensure-AgentPortRuntimeDirs
Refresh-Models
Refresh-Runtime
Set-Log 'AgentPort ready. One profile controls TextGen and the Harness together.' 'ok'
[void]$Window.ShowDialog()