# wai installer for Windows. Installs Bun and the Claude CLI if missing, links the addon into
# WoW: Forever (directory junction, no admin needed), creates the slot addons and starts the
# bridge at logon (Task Scheduler).
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -WowDir "D:\Games\World of Warcraft\_forever_"
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
param([string]$WowDir = "", [switch]$Uninstall)
$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Bridge = Join-Path $Root "bridge"
$Task = "wai bridge"

function Say($msg) { Write-Host "wai " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Fail($msg) { Write-Host "wai $msg" -ForegroundColor Red; exit 1 }

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'bun.exe'" | Where-Object { $_.CommandLine -like "*src/index.ts*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Say "Bridge stopped and removed from logon tasks. Delete Interface\AddOns\wai* in WoW to remove the addon."
    exit 0
}

# 1. Bun
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Say "Installing Bun..."
    Invoke-RestMethod https://bun.sh/install.ps1 | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
}

# 2. Claude CLI
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Say "Installing the Claude CLI..."
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}
$Claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if (-not $Claude) { Fail "Claude CLI not found after install. Open a new terminal and rerun." }
$Bun = (Get-Command bun).Source

# 3. WoW: Forever
if (-not $WowDir) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\World of Warcraft\_forever_",
        "$env:ProgramFiles\World of Warcraft\_forever_",
        "C:\World of Warcraft\_forever_",
        "D:\World of Warcraft\_forever_",
        "D:\Games\World of Warcraft\_forever_"
    )
    $WowDir = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $WowDir -or -not (Test-Path $WowDir)) {
    Fail "Couldn't find WoW: Forever. Run: install.ps1 -WowDir ""C:\path\to\World of Warcraft\_forever_"""
}
Say "WoW: Forever at $WowDir"

@{ wowDir = $WowDir; claudePath = $Claude } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $Bridge "config.json")

# 4. Bridge + addon
Push-Location $Bridge
& $Bun install
& $Bun run setup
Pop-Location

# 5. Start the bridge now and at every logon (hidden window, output to bridge.log).
$log = Join-Path $Bridge "bridge.log"
$command = "Set-Location '$Bridge'; & '$Bun' src/index.ts *> '$log'"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$command`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $Task
Say "Bridge running (log: $log) and set to start at logon."

& $Claude -p "reply with ok" --output-format json *> $null
if ($LASTEXITCODE -ne 0) { Say "Sign in to Claude once: run 'claude' in a terminal and follow the prompts." }
Say "Done. Restart WoW, then type /wai in game."
