#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$Checksums
)

$ErrorActionPreference = 'Stop'

$installerFile = Get-Item -LiteralPath $Installer
$checksumFile = Get-Item -LiteralPath $Checksums
$fileName = $installerFile.Name

$matchingLine = Get-Content -LiteralPath $checksumFile.FullName |
    Where-Object { $_ -match ('^[0-9a-fA-F]{64}\s+\*?' + [regex]::Escape($fileName) + '$') } |
    Select-Object -First 1

if (-not $matchingLine) {
    throw "A fajlhoz nem talalhato bejegyzes a checksum fajlban: $fileName"
}

$expected = ($matchingLine -split '\s+', 2)[0].ToLowerInvariant()
$actual = (Get-FileHash -LiteralPath $installerFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Fajl:    $fileName"
Write-Host "Elvart:  $expected"
Write-Host "Kapott:  $actual"

if ($actual -ne $expected) {
    throw 'A SHA-256 ellenorzes SIKERTELEN. Ne futtasd a telepitot.'
}

Write-Host 'A SHA-256 ellenorzes sikeres.' -ForegroundColor Green
