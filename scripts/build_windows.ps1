param([string]$RequestedTag = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dist = Join-Path $root 'dist'
$work = Join-Path $env:TEMP ("jsignpdf-win-build-" + [Guid]::NewGuid().ToString('N'))
$driverUrl = 'https://www.hypersecu.com/_files/archives/5aae8d_02fba2ca3532483c91e6cd958874b1e4.zip?dn=HyperPKI-HYP2003-Middleware-Windows-v1.1.25.731.zip'
$driverSha256 = 'cc77ea230cbc2216d0ef7bf3a7d79b14c4c3204a69577b918d1ba781fa2fe350'
New-Item -ItemType Directory -Force -Path $work, $dist | Out-Null

function Get-PeMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        return $reader.ReadUInt16()
    } finally { $reader.Dispose(); $stream.Dispose() }
}

try {
    if ($RequestedTag) {
        $api = "https://api.github.com/repos/intoolswetrust/jsignpdf/releases/tags/$RequestedTag"
    } else {
        $api = 'https://api.github.com/repos/intoolswetrust/jsignpdf/releases/latest'
    }
    $release = Invoke-RestMethod -Uri $api
    $version = ([string]$release.tag_name -replace '^JSignPdf_', '') -replace '_', '.'
    $asset = $release.assets | Where-Object { $_.name -like 'jsignpdf-*-windows-x64.zip' } | Select-Object -First 1
    if (-not $asset -or $asset.digest -notlike 'sha256:*') { throw 'No checksum-bearing Windows x64 ZIP found' }
    $archive = Join-Path $work $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $archive
    if ((Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() -ne ([string]$asset.digest).Substring(7).ToLowerInvariant()) {
        throw 'Upstream checksum mismatch'
    }
    $upstream = Join-Path $work 'upstream'
    Expand-Archive $archive $upstream
    $original = Get-ChildItem $upstream -Recurse -File -Filter 'JSignPdf.exe' | Select-Object -First 1
    if (-not $original) { throw 'Unable to locate upstream Windows launcher' }
    $appRoot = $original.Directory
    while ($appRoot -and -not (Test-Path (Join-Path $appRoot.FullName 'app'))) { $appRoot = $appRoot.Parent }
    if (-not $appRoot) { throw 'Unable to locate upstream Windows application root' }

    $driverArchive = Join-Path $work 'driver.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $driverUrl -OutFile $driverArchive
    if ((Get-FileHash -Algorithm SHA256 $driverArchive).Hash.ToLowerInvariant() -ne $driverSha256) { throw 'Windows driver checksum mismatch' }
    $driverOuter = Join-Path $work 'driver-outer'
    Expand-Archive $driverArchive $driverOuter
    $setup = Get-ChildItem $driverOuter -Recurse -File -Filter 'HYP2003Setup_*.exe' | Select-Object -First 1
    $driverInner = Join-Path $work 'driver-inner'
    New-Item -ItemType Directory -Path $driverInner | Out-Null
    & 7z x -y "-o$driverInner" $setup.FullName | Out-Null
    $driver = Get-ChildItem $driverInner -Recurse -File -Filter 'eps2003csp11*.dll' |
        Where-Object { (Get-PeMachine $_.FullName) -eq 0x8664 } | Select-Object -First 1
    if (-not $driver) { throw 'No x64 eps2003 PKCS#11 DLL found in official middleware' }

    $output = Join-Path $dist 'JSignPDF-AllInOne-windows-x64'
    Remove-Item -Recurse -Force $output -ErrorAction SilentlyContinue
    Copy-Item -Recurse $appRoot.FullName $output
    $integration = Join-Path $output 'AllInOne'
    New-Item -ItemType Directory -Path $integration | Out-Null
    Copy-Item $driver.FullName (Join-Path $integration 'eps2003csp11.dll')
    Copy-Item (Join-Path $root 'templates\update-windows.ps1') $integration
    Set-Content -NoNewline (Join-Path $integration 'original-executable') ($original.FullName.Substring($appRoot.FullName.Length + 1))
    Set-Content -NoNewline (Join-Path $integration 'version') $version
    Add-Type -TypeDefinition (Get-Content (Join-Path $root 'templates\WindowsLauncher.cs') -Raw) `
        -Language CSharp -OutputAssembly (Join-Path $output 'JSignPDF-AllInOne.exe') -OutputType WindowsApplication

    $outputZip = Join-Path $dist "JSignPDF-AllInOne-$version-windows-x64.zip"
    Remove-Item -Force $outputZip -ErrorAction SilentlyContinue
    Compress-Archive -Path $output -DestinationPath $outputZip
    $hash = (Get-FileHash -Algorithm SHA256 $outputZip).Hash.ToLowerInvariant()
    Set-Content ("$outputZip.sha256") "$hash  $(Split-Path -Leaf $outputZip)"
    Set-Content (Join-Path $dist 'VERSION') $version
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
