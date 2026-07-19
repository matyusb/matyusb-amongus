#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# A fajl helyi .ps1-kent es a matyusb.org rovid URL-rol iwr | iex modon is futtathato.
# A telepites elott mindig megjelenik a figyelmeztetes es az ELFOGADOM megerosites.

$downgraderUrl = 'https://github.com/whichtwix/EpicGamesDowngrader/releases/download/2026.3.31/DowngradeEpic.ps1'
$releasesApi = 'https://api.github.com/repos/AU-Avengers/TOU-Mira/releases?per_page=20'

$gamesRoot = Join-Path $env:USERPROFILE 'Games'
$expectedGamePath = Join-Path $gamesRoot 'AmongUs'
$desktopPath = [Environment]::GetFolderPath('Desktop')
$desktopGamePath = Join-Path $desktopPath 'Among Us - TOU Mira'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('TOU-Mira-' + [Guid]::NewGuid().ToString('N'))
$downgradeWork = Join-Path $tempRoot 'downgrader'
$downgraderFile = Join-Path $downgradeWork 'DowngradeEpic.ps1'
$extractPath = Join-Path $tempRoot 'extract'
$zipPath = Join-Path $tempRoot 'TOU-Mira.zip'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


function Confirm-InstallerNotice {
    param([Parameter(Mandatory = $true)][string]$Edition)

    Write-Host ''
    Write-Host 'FONTOS BIZTONSAGI FIGYELMEZTETES' -ForegroundColor Yellow
    Write-Host '================================' -ForegroundColor Yellow
    Write-Host ("Ez egy nem hivatalos, kozossegi telepito az Among Us TOU Mira modhoz ({0})." -f $Edition)
    Write-Host 'Nem kapcsolodik az Innersloth, Valve, Steam, Epic Games vagy Microsoft cegekhez.'
    Write-Host 'A telepito jatekfajlokat modosit, folyamatokat allithat le, es kulso forrasokbol tolt le fajlokat.'
    Write-Host 'A projekt ingyenes; fizetett tamogatas, garancia es mukodesi garancia nincs.'
    Write-Host 'Javasolt biztonsagi mentes keszitese es a forraskod atnezese.'
    Write-Host ''
    Write-Host 'Jelszot soha ne irj kozvetlenul ebbe a PowerShell-szkriptbe.' -ForegroundColor Yellow
    Write-Host 'A Steam/Epic hitelesitesi adatokat csak a megfelelo kliens vagy hitelesitesi oldal kerheti.' -ForegroundColor Yellow
    Write-Host ''

    $answer = Read-Host 'A folytatashoz ird be pontosan: ELFOGADOM'
    if ($answer -cne 'ELFOGADOM') {
        throw 'A telepites megszakitva: a figyelmeztetest nem fogadtad el.'
    }
}

function Assert-FileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "A fajl nem talalhato ellenorzeshez: $Path"
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $ExpectedHash.Trim().ToLowerInvariant()

    if ($actual -ne $expected) {
        throw ("SHA-256 elteres ({0}). Vart: {1}; kapott: {2}" -f $Label, $expected, $actual)
    }

    Write-Host ("SHA-256 rendben: {0}" -f $Label) -ForegroundColor Green
}

function Assert-GitHubAssetDigest {
    param(
        [Parameter(Mandatory = $true)]$Asset,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $digest = [string]$Asset.digest
    if ([string]::IsNullOrWhiteSpace($digest) -or $digest -notmatch '(?i)^sha256:[0-9a-f]{64}$') {
        throw ("A GitHub API nem adott hasznalhato SHA-256 digestet ehhez az assethez: {0}" -f $Asset.name)
    }

    $expected = $digest.Substring('sha256:'.Length)
    Assert-FileSha256 -Path $Path -ExpectedHash $expected -Label $Asset.name
}

function Test-DirectoryWritable {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }

        $probe = Join-Path $Path ('.tou-write-test-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch {
        return $false
    }
}

function Repair-GamesFolderPermissions {
    param([Parameter(Mandatory = $true)][string]$Path)

    $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $helperPath = Join-Path $env:TEMP ('Fix-Games-Permissions-' + [Guid]::NewGuid().ToString('N') + '.ps1')

    $safePath = $Path.Replace("'", "''")
    $safeAccount = $account.Replace("'", "''")

    $helperCode = @"
`$ErrorActionPreference = 'Stop'
`$target = '$safePath'
`$account = '$safeAccount'

if (-not (Test-Path -LiteralPath `$target -PathType Container)) {
    New-Item -ItemType Directory -Path `$target -Force | Out-Null
}

Write-Host 'A Games mappa tulajdonosanak es jogosultsagainak javitasa...' -ForegroundColor Cyan

& icacls.exe `$target /setowner `$account /T /C /Q
if (`$LASTEXITCODE -ne 0) {
    throw "A tulajdonos beallitasa sikertelen. ICACLS kod: `$LASTEXITCODE"
}

`$grant = "`${account}:(OI)(CI)F"
& icacls.exe `$target /inheritance:e /grant:r `$grant /T /C /Q
if (`$LASTEXITCODE -ne 0) {
    throw "A jogosultsag beallitasa sikertelen. ICACLS kod: `$LASTEXITCODE"
}

Write-Host 'A jogosultsag javitasa kesz.' -ForegroundColor Green
Start-Sleep -Seconds 2
"@

    Set-Content -LiteralPath $helperPath -Value $helperCode -Encoding ASCII

    try {
        Write-Host ''
        Write-Host "Nincs irasi jog ehhez a mappahoz: $Path" -ForegroundColor Yellow
        Write-Host 'Most megjelenik egy rendszergazdai engedelykeres csak a mappa jogosultsaganak javitasahoz.' -ForegroundColor Yellow

        $process = Start-Process powershell.exe `
            -Verb RunAs `
            -Wait `
            -PassThru `
            -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', ('"' + $helperPath + '"')
            )

        if ($process.ExitCode -ne 0) {
            throw "A jogosultsag-javito folyamat hibakoddal allt le: $($process.ExitCode)"
        }
    }
    finally {
        Remove-Item -LiteralPath $helperPath -Force -ErrorAction SilentlyContinue
    }
}

function Find-AmongUsFolder {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Games\AmongUs'),
        (Join-Path $env:USERPROFILE 'Games\Among Us')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return $candidate
        }
    }

    if (Test-Path -LiteralPath $gamesRoot -PathType Container) {
        $exe = Get-ChildItem -LiteralPath $gamesRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Among Us.exe', 'AmongUs.exe') } |
            Select-Object -First 1

        if ($exe) {
            return $exe.Directory.FullName
        }
    }

    return $null
}

try {
    if (Test-IsAdministrator) {
        throw 'Ezt a telepitot normal felhasznalokent futtasd, ne rendszergazdakent.'
    }

    Confirm-InstallerNotice -Edition 'Epic Games'

    Write-Host '0/5 - Celmappa ellenorzese...' -ForegroundColor Cyan

    if (-not (Test-DirectoryWritable -Path $gamesRoot)) {
        Repair-GamesFolderPermissions -Path $gamesRoot
    }

    if (-not (Test-DirectoryWritable -Path $gamesRoot)) {
        throw "A mappa tovabbra sem irhato: $gamesRoot"
    }

    New-Item -ItemType Directory -Path $downgradeWork -Force | Out-Null
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Write-Host '1/5 - Downgrader letoltese es futtatasa...' -ForegroundColor Cyan

    Invoke-WebRequest `
        -Uri $downgraderUrl `
        -OutFile $downgraderFile `
        -UseBasicParsing

    if (-not (Test-Path -LiteralPath $downgraderFile -PathType Leaf)) {
        throw 'A DowngradeEpic.ps1 letoltese sikertelen volt.'
    }

    Assert-FileSha256 -Path $downgraderFile -ExpectedHash 'effbae48554296e2999a3864b0eeb666584d83bae34fbb42d604d0a89d236a11' -Label 'DowngradeEpic.ps1 2026.3.31'

    Write-Host 'A downgrader Epic bejelentkezesi kodot kerhet.' -ForegroundColor Yellow
    Write-Host 'A vegen nyomj Entert, amikor a downgrader ezt keri.' -ForegroundColor Yellow

    Push-Location $downgradeWork
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $downgraderFile
        $downgradeExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($downgradeExitCode -ne 0) {
        throw "A downgrader hibakoddal allt le: $downgradeExitCode"
    }

    $gamePath = Find-AmongUsFolder
    if (-not $gamePath) {
        throw "Az Among Us mappa a downgrade utan sem talalhato itt: $expectedGamePath"
    }

    Write-Host ("Among Us mappa: {0}" -f $gamePath) -ForegroundColor Green
    Write-Host '2/5 - Legujabb TOU Mira Epic/MS Store csomag keresese...' -ForegroundColor Cyan

    $headers = @{
        'User-Agent' = 'TOU-Mira-PowerShell-Installer'
        'Accept' = 'application/vnd.github+json'
    }

    $releases = Invoke-RestMethod -Uri $releasesApi -Headers $headers -Method Get
    $selected = $null

    foreach ($release in @($releases)) {
        if ($release.draft) {
            continue
        }

        $assets = @($release.assets)

        $asset = $assets |
            Where-Object {
                $_.name -match '(?i)\.zip$' -and
                $_.name -match '(?i)(epic|ms.?store)' -and
                $_.name -match '(?i)x64'
            } |
            Select-Object -First 1

        if (-not $asset) {
            $asset = $assets |
                Where-Object {
                    $_.name -match '(?i)\.zip$' -and
                    $_.name -match '(?i)(epic|ms.?store)'
                } |
                Select-Object -First 1
        }

        if ($asset) {
            $selected = [PSCustomObject]@{
                TagName = $release.tag_name
                Asset = $asset
            }
            break
        }
    }

    if (-not $selected) {
        throw 'Nem talalhato Epic/MS Store ZIP a TOU Mira kiadasok kozott.'
    }

    Write-Host ("Kivalasztva: {0} - {1}" -f $selected.TagName, $selected.Asset.name) -ForegroundColor Green
    Write-Host '3/5 - Mod letoltese es kicsomagolasa...' -ForegroundColor Cyan

    Invoke-WebRequest `
        -Uri $selected.Asset.browser_download_url `
        -OutFile $zipPath `
        -UseBasicParsing

    Assert-GitHubAssetDigest -Asset $selected.Asset -Path $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $sourcePath = $extractPath

    $markerFile = Get-ChildItem -LiteralPath $extractPath -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('winhttp.dll', 'doorstop_config.ini') } |
        Select-Object -First 1

    if ($markerFile) {
        $sourcePath = $markerFile.Directory.FullName
    }
    else {
        $bepInExFolder = Get-ChildItem -LiteralPath $extractPath -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'BepInEx' } |
            Select-Object -First 1

        if ($bepInExFolder) {
            $sourcePath = $bepInExFolder.Parent.FullName
        }
        else {
            $topLevelItems = @(Get-ChildItem -LiteralPath $extractPath -Force)
            if ($topLevelItems.Count -eq 1 -and $topLevelItems[0].PSIsContainer) {
                $sourcePath = $topLevelItems[0].FullName
            }
        }
    }

    Write-Host '4/5 - Fajlok bemasolasa az Among Us mappaba...' -ForegroundColor Cyan

    & robocopy.exe $sourcePath $gamePath /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    $robocopyExitCode = $LASTEXITCODE

    if ($robocopyExitCode -gt 7) {
        throw "A masolas sikertelen. Robocopy hibakod: $robocopyExitCode"
    }

    Write-Host '5/5 - A modolt jatek masolasa az Asztalra...' -ForegroundColor Cyan

    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        throw 'Az Asztal mappaja nem talalhato.'
    }

    if (Test-Path -LiteralPath $desktopGamePath) {
        $backupPath = $desktopGamePath + ' - regi-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Write-Host ("A meglevo asztali mappa atnevezese: {0}" -f $backupPath) -ForegroundColor Yellow
        Move-Item -LiteralPath $desktopGamePath -Destination $backupPath -Force
    }

    New-Item -ItemType Directory -Path $desktopGamePath -Force | Out-Null

    & robocopy.exe $gamePath $desktopGamePath /MIR /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    $desktopCopyExitCode = $LASTEXITCODE

    if ($desktopCopyExitCode -gt 7) {
        throw "Az Asztalra masolas sikertelen. Robocopy hibakod: $desktopCopyExitCode"
    }

    Write-Host ''
    Write-Host 'A TOU Mira telepitese befejezodott.' -ForegroundColor Green
    Write-Host ("Eredeti modolt mappa: {0}" -f $gamePath) -ForegroundColor Green
    Write-Host ("Asztali masolat: {0}" -f $desktopGamePath) -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host 'Hiba tortent:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Nyomj Entert a bezarashoz'
    return
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Read-Host 'Nyomj Entert a bezarashoz'
