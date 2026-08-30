<#
.SYNOPSIS
    Downloads and applies the "Yaru" Windows 11 theme from GitHub in one shot:
      - Desktop wallpaper  -> bloom.png
      - Lock screen image  -> bloom_lockscreen.png
      - Accent color       -> #FF7446
      - Installs yaru.theme

.USAGE (run in an elevated PowerShell for full lock-screen support)
    irm https://raw.githubusercontent.com/adinmaccabee/Windows-11-Yaru/main/yaru.ps1 | iex

    Update the GitHubRepo variable below if your repo/branch/path differs.
#>

# ---------- Config: EDIT THESE IF YOUR REPO DIFFERS ----------
$GitHubUser   = "adinmaccabee"
$GitHubRepo   = "Windows-11-Yaru"     # <-- change if you name the repo something else
$GitHubBranch = "main"            # <-- change to "master" if that's your default branch
$BaseUrl      = "https://raw.githubusercontent.com/$GitHubUser/$GitHubRepo/$GitHubBranch"

$AccentColorHex = "FF7446"   # RRGGBB

# ---------- Paths ----------
$DestFolder   = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Themes\Yaru"
$WallpaperDst = Join-Path $DestFolder "bloom.png"
$LockscreenDst= Join-Path $DestFolder "bloom_lockscreen.png"
$ThemeDst     = Join-Path $DestFolder "yaru.theme"

New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null

# ---------- Helpers ----------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-HexToAccentDword {
    param([string]$Hex)
    $r = [Convert]::ToByte($Hex.Substring(0,2),16)
    $g = [Convert]::ToByte($Hex.Substring(2,2),16)
    $b = [Convert]::ToByte($Hex.Substring(4,2),16)
    $a = 0xFF
    return ([uint32]$a -shl 24) -bor ([uint32]$b -shl 16) -bor ([uint32]$g -shl 8) -bor $r
}

function Get-RemoteFile {
    param([string]$Path, [string]$Destination)
    $url = "$BaseUrl/$Path"
    try {
        Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing
        return $true
    } catch {
        Write-Warning "Couldn't download $url ($($_.Exception.Message))"
        return $false
    }
}

# ---------- Download assets ----------
Write-Host "Downloading assets from $BaseUrl ..." -ForegroundColor Cyan
$haveWallpaper  = Get-RemoteFile -Path "bloom.png"            -Destination $WallpaperDst
$haveLockscreen = Get-RemoteFile -Path "bloom_lockscreen.png" -Destination $LockscreenDst
$haveTheme      = Get-RemoteFile -Path "yaru.theme"            -Destination $ThemeDst

if (-not $haveWallpaper) {
    Write-Error "Wallpaper download failed - check GitHubUser/GitHubRepo/GitHubBranch at the top of this script, and that the repo is public."
    exit 1
}

# ---------- 1. Set desktop wallpaper ----------
#Add-Type @"
#using System;
#using System.Runtime.InteropServices;
#public class Wallpaper {
#    [DllImport("user32.dll", CharSet = CharSet.Auto)]
#    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
#}
#"@ -ErrorAction SilentlyContinue
#
#Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
#Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper  -Value "0"
#[Wallpaper]::SystemParametersInfo(20, 0, $WallpaperDst, 3) | Out-Null
#Write-Host "Wallpaper set." -ForegroundColor Green

# ---------- 2. Set lock screen image ----------
#if ($haveLockscreen) {
#    if (Test-IsAdmin) {
#        $polKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
#        New-Item -Path $polKey -Force | Out-Null
#        Set-ItemProperty -Path $polKey -Name "LockScreenImage" -Value $LockscreenDst -Type String
#        Write-Host "Lock screen set." -ForegroundColor Green
#    } else {
#        Write-Warning "Not running as Administrator - skipped lock screen (re-run elevated to set it)."
#    }
#}

# ---------- 3. Set accent color ----------
$accentPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
if (-not (Test-Path $accentPath)) { New-Item -Path $accentPath -Force | Out-Null }

$dword = Convert-HexToAccentDword -Hex $AccentColorHex
Set-ItemProperty -Path $accentPath -Name "AccentColorMenu" -Value $dword -Type DWord
Set-ItemProperty -Path $accentPath -Name "StartColorMenu"  -Value $dword -Type DWord

$palette = [byte[]](
    0xFD,0xB6,0x9E,0xFF,
    0xFC,0x9B,0x7B,0xFF,
    0xFF,0x87,0x5F,0xFF,
    0xFF,0x74,0x46,0xFF,
    0xFF,0x60,0x2C,0xFF,
    0xFE,0x4D,0x12,0xFF,
    0xEE,0x3B,0x00,0xFF,
    0x88,0x17,0x98,0x00
)
Set-ItemProperty -Path $accentPath -Name "AccentPalette" -Value $palette -Type Binary
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -Value 0 -Type DWord -ErrorAction SilentlyContinue

Write-Host "Accent color set to #$AccentColorHex" -ForegroundColor Green

# ---------- 4. Set dark mode ----------
$personalizePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
if (-not (Test-Path $personalizePath)) { New-Item -Path $personalizePath -Force | Out-Null }
Set-ItemProperty -Path $personalizePath -Name "AppsUseLightTheme"   -Value 0 -Type DWord
Set-ItemProperty -Path $personalizePath -Name "SystemUsesLightTheme" -Value 0 -Type DWord
Write-Host "Dark mode enabled (apps + system)." -ForegroundColor Green

# ---------- 5. Install the .theme file ----------
if ($haveTheme) {
    # Rewrite the Wallpaper= line with the literal, fully-resolved path -
    # some Windows builds don't reliably expand %LOCALAPPDATA% inside .theme files.
    $themeContent = Get-Content -Path $ThemeDst -Raw
    $themeContent = $themeContent -replace 'Wallpaper=.*', "Wallpaper=$WallpaperDst"
    Set-Content -Path $ThemeDst -Value $themeContent -Encoding UTF8

    Start-Process $ThemeDst
    Write-Host "yaru.theme launched - Windows will install it under Settings > Personalization > Themes." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Sign out and back in (or restart Explorer) for everything to fully apply:" -ForegroundColor Cyan
Write-Host "  Stop-Process -Name explorer -Force; Start-Process explorer"
