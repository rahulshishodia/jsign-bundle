param(
    [Parameter(Mandatory = $true)][string]$AppDir,
    [Parameter(Mandatory = $true)][int]$AppPid
)

$ErrorActionPreference = 'Stop'
$currentVersion = (Get-Content (Join-Path $AppDir 'AllInOne\version') -Raw).Trim()
$cacheDir = Join-Path $env:LOCALAPPDATA 'JSignPdf-AllInOne\Cache'
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

try {
    $release = Invoke-RestMethod -TimeoutSec 10 -Uri 'https://api.github.com/repos/rahulshishodia/jsign-bundle/releases/latest'
} catch { exit 0 }
$latestVersion = [string]$release.tag_name -replace '^v', ''
$asset = $release.assets | Where-Object { $_.name -like 'JSignPDF-AllInOne-*-windows-x64.zip' } | Select-Object -First 1
if (-not $asset -or $latestVersion -eq $currentVersion -or $asset.digest -notlike 'sha256:*') { exit 0 }

Add-Type -AssemblyName PresentationFramework
$choice = [System.Windows.MessageBox]::Show(
    "JSignPDF $latestVersion is available. Download and install it after JSignPDF closes?",
    'JSignPDF Update', 'YesNo', 'Information')
if ($choice -ne 'Yes') { exit 0 }

$work = Join-Path $env:TEMP ("jsignpdf-update-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $archive = Join-Path $work 'update.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $archive
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    $expected = ([string]$asset.digest).Substring(7).ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Release checksum mismatch' }
    Expand-Archive -Path $archive -DestinationPath (Join-Path $work 'stage')
    $newApp = Join-Path $work 'stage\JSignPDF-AllInOne-windows-x64'
    if (-not (Test-Path (Join-Path $newApp 'JSignPDF-AllInOne.exe'))) { throw 'Invalid update archive' }
    Wait-Process -Id $AppPid -ErrorAction SilentlyContinue
    $backup = "$AppDir.previous-$currentVersion-$(Get-Date -Format yyyyMMddHHmmss)"
    Move-Item $AppDir $backup
    try { Move-Item $newApp $AppDir } catch { Move-Item $backup $AppDir; throw }
    Start-Process (Join-Path $AppDir 'JSignPDF-AllInOne.exe')
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

