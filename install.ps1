# Installs wai from GitHub Releases (Windows): downloads wai-windows-x64.exe, checks its SHA-256,
# puts it in %USERPROFILE%\.local\bin, records the install so `wai update` can replace it later,
# then runs `wai install` (links the addon into WoW: Forever and starts the bridge at logon).
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dan-myles/wai/main/install.ps1)))
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Version v0.1.0 -WowDir "D:\Games\World of Warcraft\_forever_"
#
# The repo is private: with the GitHub CLI signed in (`gh auth login`) downloads just work.
param([string]$Version = "", [string]$WowDir = "")
$ErrorActionPreference = "Stop"

$Repo = if ($env:WAI_REPO) { $env:WAI_REPO } else { "dan-myles/wai" }
# One Windows build; ARM64 Windows runs it under emulation.
$Asset = "wai-windows-x64.exe"

function Say($msg) { Write-Host "wai " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Fail($msg) { Write-Host "wai $msg" -ForegroundColor Red; exit 1 }

$tmp = Join-Path $env:TEMP "wai-install-$(Get-Random)"
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    Say "Downloading $Asset $(if ($Version) { $Version } else { '(latest)' })..."
    $ghReady = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        & gh auth status *> $null
        $ghReady = $LASTEXITCODE -eq 0
    }
    if ($ghReady) {
        $ghArgs = @("release", "download")
        if ($Version) { $ghArgs += $Version }
        $ghArgs += @("--repo", $Repo, "--pattern", $Asset, "--pattern", "SHA256SUMS", "--dir", $tmp)
        & gh @ghArgs
        if ($LASTEXITCODE -ne 0) { Fail "gh release download failed" }
    } else {
        $base = if ($Version) { "https://github.com/$Repo/releases/download/$Version" } else { "https://github.com/$Repo/releases/latest/download" }
        try {
            Invoke-WebRequest "$base/$Asset" -OutFile (Join-Path $tmp $Asset) -UseBasicParsing
            Invoke-WebRequest "$base/SHA256SUMS" -OutFile (Join-Path $tmp "SHA256SUMS") -UseBasicParsing
        } catch {
            Fail "download failed. The repo is private: install the GitHub CLI and run 'gh auth login' first."
        }
    }

    $expected = (Get-Content (Join-Path $tmp "SHA256SUMS") | Where-Object { $_ -match " $([regex]::Escape($Asset))$" }) -split "\s+" | Select-Object -First 1
    $actual = (Get-FileHash (Join-Path $tmp $Asset) -Algorithm SHA256).Hash.ToLower()
    if (-not $expected -or $expected -ne $actual) { Fail "checksum mismatch for $Asset; nothing was installed" }

    $binDir = Join-Path $env:USERPROFILE ".local\bin"
    $bin = Join-Path $binDir "wai.exe"
    New-Item -ItemType Directory -Force $binDir, (Join-Path $env:USERPROFILE ".wai") | Out-Null
    # A running wai.exe (the bridge) can be renamed but not overwritten.
    if (Test-Path $bin) { Move-Item -Force $bin "$bin.old" }
    Move-Item -Force (Join-Path $tmp $Asset) $bin

    $installed = ((& $bin version) -split " ")[1]
    @{ managed = $true; version = $installed; path = $bin; installedAt = (Get-Date).ToUniversalTime().ToString("o") } |
        ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $env:USERPROFILE ".wai\install.json")
    Say "Installed wai $installed to $bin"

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($userPath -split ";" | Where-Object { $_ -eq $binDir })) {
        [Environment]::SetEnvironmentVariable("Path", "$binDir;$userPath", "User")
        $env:Path = "$binDir;$env:Path"
        Say "Added $binDir to your PATH (open a new terminal to use 'wai')."
    }

    if ($WowDir) { & $bin install --wow $WowDir } else { & $bin install }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
