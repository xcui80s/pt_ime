#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PTT IME Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------
# [1/4] AutoHotkey v2
# ----------------------------------------------------------------------
Write-Host "[1/4] AutoHotkey v2..." -ForegroundColor Yellow

$ahkInstalled = (Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue) -or
                (Test-Path "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") -or
                (Test-Path "$env:LocalAppData\Programs\AutoHotkey\v2\AutoHotkey64.exe") -or
                (Get-ItemProperty "HKCU:\SOFTWARE\AutoHotkey" -ErrorAction SilentlyContinue)

if ($ahkInstalled) {
    Write-Host "  Already installed." -ForegroundColor Green
} else {
    try {
        Write-Host "  Downloading AutoHotkey v2..."
        $installer = "$env:TEMP\ahk-v2.exe"
        Invoke-WebRequest "https://www.autohotkey.com/download/ahk-v2.exe" -OutFile $installer -UseBasicParsing
        Write-Host "  Installing (requires UAC prompt)..."
        Start-Process $installer -ArgumentList "/S" -Wait -Verb RunAs
        Remove-Item $installer -Force
        Write-Host "  AutoHotkey v2 installed." -ForegroundColor Green
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ----------------------------------------------------------------------
# [2/4] FFmpeg
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] FFmpeg..." -ForegroundColor Yellow

$ffmpegCmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue

if ($ffmpegCmd) {
    Write-Host "  Already on PATH: $($ffmpegCmd.Source)" -ForegroundColor Green
} else {
    $installed = $false

    # Try winget first
    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        try {
            Write-Host "  Installing via winget..."
            winget install Gyan.FFmpeg --silent --accept-package-agreements --accept-source-agreements
            $installed = $true
        } catch {
            Write-Host "  winget failed, falling back to direct download..." -ForegroundColor Yellow
        }
    }

    # Fallback: download ZIP from gyan.dev
    if (-not $installed) {
        try {
            Write-Host "  Downloading FFmpeg (this may take a minute)..."
            $zip = "$env:TEMP\ffmpeg.zip"
            Invoke-WebRequest "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $zip -UseBasicParsing
            $dest = "$env:LOCALAPPDATA\ffmpeg"
            Write-Host "  Extracting to $dest..."
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Expand-Archive $zip $dest -Force
            Remove-Item $zip -Force
            $binDir = (Get-ChildItem $dest -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1).Directory.FullName
            if (-not $binDir) { throw "ffmpeg.exe not found after extraction" }
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$binDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$userPath;$binDir", "User")
            }
            $env:PATH += ";$binDir"
            $installed = $true
        } catch {
            Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }

    # Verify
    $ffmpegCmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if ($ffmpegCmd) {
        Write-Host "  FFmpeg installed." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: ffmpeg not found on PATH yet." -ForegroundColor Yellow
        Write-Host "  If installed via winget, close this window and rerun setup.bat." -ForegroundColor Yellow
        exit 1
    }
}

# ----------------------------------------------------------------------
# [3/4] Audio device
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] Audio device..." -ForegroundColor Yellow

try {
    # Run via cmd.exe so all output is plain strings — avoids ErrorRecord
    # objects from 2>&1 triggering $ErrorActionPreference = Stop
    $dshowOutput = cmd.exe /c "ffmpeg -list_devices true -f dshow -i dummy 2>&1"
    # Each device line ends with (audio) or (video) — match audio lines directly
    $devices = @()
    foreach ($line in $dshowOutput) {
        if ($line -match '\] "([^"]+)" \(audio\)') { $devices += $Matches[1] }
    }
} catch {
    Write-Host "  ERROR enumerating audio devices: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($devices.Count -eq 0) {
    Write-Host "  ERROR: No audio devices found. Check FFmpeg dshow support." -ForegroundColor Red
    exit 1
}

$selectedDevice = ""
if ($devices.Count -eq 1) {
    $selectedDevice = $devices[0]
    Write-Host "  Auto-selected: $selectedDevice" -ForegroundColor Green
} else {
    Write-Host "  Audio devices found:"
    for ($i = 0; $i -lt $devices.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $devices[$i])
    }
    do {
        $choice = Read-Host "  Select device [1-$($devices.Count)]"
        $idx = [int]$choice - 1
    } while ($idx -lt 0 -or $idx -ge $devices.Count)
    $selectedDevice = $devices[$idx]
    Write-Host "  Selected: $selectedDevice" -ForegroundColor Green
}

# ----------------------------------------------------------------------
# [4/4] Whisper server IP
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] Whisper server IP..." -ForegroundColor Yellow

$localIP = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
    Select-Object -First 1).IPAddress

$defaultHost = switch -Wildcard ($localIP) {
    "192.168.86.*" { "192.168.86.45" }
    "192.168.68.*" { "192.168.68.55" }
    default        { "127.0.0.1" }
}

Write-Host ("  Local IP      : {0}" -f $localIP)
Write-Host ("  Server default: {0}" -f $defaultHost)
$inputHost = Read-Host "  Whisper server IP (press Enter for $defaultHost)"
$whisperHost = if ($inputHost.Trim()) { $inputHost.Trim() } else { $defaultHost }
Write-Host "  Using: $whisperHost" -ForegroundColor Green

# ----------------------------------------------------------------------
# Update ptt.ahk
# ----------------------------------------------------------------------
Write-Host ""
$ahkFile = Join-Path $PSScriptRoot "ptt.ahk"
if (-not (Test-Path $ahkFile)) {
    Write-Host "ERROR: ptt.ahk not found at $ahkFile" -ForegroundColor Red
    exit 1
}

$content = [IO.File]::ReadAllText($ahkFile, [Text.Encoding]::UTF8)
$content = $content -replace 'AUDIO_DEVICE := "[^"]*"', "AUDIO_DEVICE := `"$selectedDevice`""
$content = $content -replace 'WHISPER_HOST := "[^"]*"', "WHISPER_HOST := `"$whisperHost`""
[IO.File]::WriteAllText($ahkFile, $content, (New-Object System.Text.UTF8Encoding $false))

Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  ptt.ahk updated:" -ForegroundColor Green
Write-Host "    AUDIO_DEVICE = $selectedDevice"
Write-Host "    WHISPER_HOST = $whisperHost"
Write-Host ""
Write-Host "  Double-click ptt.ahk to start. Hold F8 to record." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
