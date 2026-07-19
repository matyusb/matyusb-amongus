#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$SteamUrl = 'https://matyusb.org/steam',
    [string]$EpicUrl = 'https://matyusb.org/epicgames',
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('TOU-Mira-Endpoint-Test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Test-InstallerEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        throw "Local installer is missing: $LocalPath"
    }

    $downloadPath = Join-Path $tempRoot ($Name + '.ps1')
    Write-Host "Downloading $Name installer from $Url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $downloadPath

    $text = Get-Content -LiteralPath $downloadPath -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Name endpoint returned an empty response."
    }

    try {
        [void][ScriptBlock]::Create($text)
    }
    catch {
        throw "$Name endpoint did not return valid PowerShell source: $($_.Exception.Message)"
    }

    $localHash = (Get-FileHash -LiteralPath $LocalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host "Local SHA-256:  $localHash"
    Write-Host "Remote SHA-256: $remoteHash"

    if ($localHash -ne $remoteHash) {
        throw "$Name endpoint does not exactly match the committed installer."
    }

    Write-Host "$Name endpoint verified." -ForegroundColor Green
}

try {
    Test-InstallerEndpoint `
        -Name 'Steam' `
        -Url $SteamUrl `
        -LocalPath (Join-Path $RepositoryRoot 'scripts\TOU-Mira-Telepito-Steam.ps1')

    Test-InstallerEndpoint `
        -Name 'EpicGames' `
        -Url $EpicUrl `
        -LocalPath (Join-Path $RepositoryRoot 'scripts\TOU-Mira-Telepito-Epic-Games.ps1')

    Write-Host ''
    Write-Host 'Both public installer endpoints match the committed files.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
