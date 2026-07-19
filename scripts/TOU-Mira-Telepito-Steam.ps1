#requires -Version 5.1

param(
    [string]$DesktopPath = [Environment]::GetFolderPath('Desktop'),
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Among Us',
    [string]$BetaBranch = 'public-previous'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppId = 945360
$DesktopTarget = Join-Path $DesktopPath 'Among Us - TOU Mira'
$SteamCmdUrl = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
$ReleasesApi = 'https://api.github.com/repos/AU-Avengers/TOU-Mira/releases?per_page=20'
$RemoteInstallerUrl = 'https://matyusb.org/steam'

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('TOU-Mira-Steam-AllInOne-' + [Guid]::NewGuid().ToString('N'))
$SteamCmdZip = Join-Path $TempRoot 'steamcmd.zip'
$SteamCmdRoot = Join-Path $TempRoot 'steamcmd'
$SteamCmdExe = Join-Path $SteamCmdRoot 'steamcmd.exe'
$ModZip = Join-Path $TempRoot 'TOU-Mira-Steam.zip'
$ExtractPath = Join-Path $TempRoot 'mod-extract'

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

function Assert-AuthenticodePublisher {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PublisherPattern
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw ("Ervenytelen vagy hianyzik a digitalis alairas: {0}; allapot: {1}" -f $Path, $signature.Status)
    }

    $subject = [string]$signature.SignerCertificate.Subject
    if ($subject -notmatch $PublisherPattern) {
        throw ("Varatlan alairo a fajlon: {0}; alairo: {1}" -f $Path, $subject)
    }

    Write-Host ("Digitalis alairas rendben: {0}" -f $subject) -ForegroundColor Green
}

function Copy-WithRobocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:3 /W:2 /XJ /NFL /NDL /NJH /NJS /NP
    $code = $LASTEXITCODE

    # Robocopy exit codes 0-7 mean success or success with warnings.
    if ($code -gt 7) {
        throw "A masolas sikertelen. Robocopy hibakod: $code"
    }
}

function Stop-ProcessSafely {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $Names -contains $_.ProcessName }

    if (-not $processes) {
        return
    }

    foreach ($process in $processes) {
        try { [void]$process.CloseMainWindow() } catch {}
    }

    Start-Sleep -Seconds 4

    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $Names -contains $_.ProcessName }

    if ($processes) {
        $processes | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Find-ModSourceFolder {
    param([Parameter(Mandatory = $true)][string]$Root)

    $markerFile = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('winhttp.dll', 'doorstop_config.ini') } |
        Select-Object -First 1

    if ($markerFile) {
        return $markerFile.Directory.FullName
    }

    $bepInExFolder = Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'BepInEx' } |
        Select-Object -First 1

    if ($bepInExFolder) {
        return $bepInExFolder.Parent.FullName
    }

    $topLevelItems = @(Get-ChildItem -LiteralPath $Root -Force)
    if ($topLevelItems.Count -eq 1 -and $topLevelItems[0].PSIsContainer) {
        return $topLevelItems[0].FullName
    }

    return $Root
}

# A Program Files mappa irasahoz rendszergazdai jog kell.
# Helyi .ps1 futtatasnal a helyi fajl indul ujra. iwr | iex futtatasnal
# ugyanaz a teljes telepito URL indul ujra a rendszergazdai PowerShellben.
if (-not (Test-IsAdministrator)) {
    Write-Host 'Rendszergazdai engedely szukseges a Steam Among Us mappa modositasahoz.' -ForegroundColor Yellow

    $DesktopPathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($DesktopPath))
    $GamePathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($GamePath))
    $BetaBranchEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($BetaBranch))

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $ScriptPathEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($PSCommandPath))

        $ElevatedCommand = @"
`$ErrorActionPreference = 'Stop'
`$scriptPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$ScriptPathEncoded'))
`$desktopPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$DesktopPathEncoded'))
`$gamePath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$GamePathEncoded'))
`$betaBranch = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$BetaBranchEncoded'))

try {
    & `$scriptPath -DesktopPath `$desktopPath -GamePath `$gamePath -BetaBranch `$betaBranch
}
catch {
    Write-Host ''
    Write-Host 'Nem sikerult elinditani a telepitot rendszergazdakent:' -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
    Read-Host 'Nyomj Entert a bezarashoz'
}
"@
    }
    else {
        $RemoteUrlEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($RemoteInstallerUrl))

        $ElevatedCommand = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$installerUrl = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$RemoteUrlEncoded'))
`$desktopPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$DesktopPathEncoded'))
`$gamePath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$GamePathEncoded'))
`$betaBranch = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$BetaBranchEncoded'))
`$tempInstaller = Join-Path ([IO.Path]::GetTempPath()) ('TOU-Mira-Steam-Elevated-' + [Guid]::NewGuid().ToString('N') + '.ps1')

try {
    Invoke-WebRequest -Uri `$installerUrl -UseBasicParsing -OutFile `$tempInstaller
    if (-not (Test-Path -LiteralPath `$tempInstaller -PathType Leaf) -or (Get-Item -LiteralPath `$tempInstaller).Length -eq 0) {
        throw 'Az installer URL ures vagy hianyzo fajlt adott.'
    }

    & `$tempInstaller -DesktopPath `$desktopPath -GamePath `$gamePath -BetaBranch `$betaBranch
}
catch {
    Write-Host ''
    Write-Host 'Nem sikerult letolteni vagy elinditani a telepitot rendszergazdakent:' -ForegroundColor Red
    Write-Host `$_.Exception.Message -ForegroundColor Red
    Read-Host 'Nyomj Entert a bezarashoz'
}
finally {
    Remove-Item -LiteralPath `$tempInstaller -Force -ErrorAction SilentlyContinue
}
"@
    }

    $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ElevatedCommand))

    try {
        Start-Process `
            -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $EncodedCommand) | Out-Null
    }
    catch {
        Write-Host ''
        Write-Host 'A rendszergazdai engedelykeres meg lett szakitva vagy nem sikerult.' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host 'Nyomj Entert a bezarashoz'
    }

    return
}

try {
    Confirm-InstallerNotice -Edition 'Steam'

    Write-Host 'TOU Mira Steam - teljes automatikus telepito' -ForegroundColor Cyan
    Write-Host '===========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ("Steam celmappa:  {0}" -f $GamePath)
    Write-Host ("Steam beta ag:  {0}" -f $BetaBranch)
    Write-Host ("Asztali masolat: {0}" -f $DesktopTarget)
    Write-Host ''

    if (-not (Test-Path -LiteralPath $GamePath -PathType Container)) {
        Write-Host ("A Steam Among Us mappa nem letezik, letrehozas: {0}" -f $GamePath) -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $GamePath -Force | Out-Null
    }

    Write-Host '1/7 - Among Us es Steam bezarasa...' -ForegroundColor Cyan
    Stop-ProcessSafely -Names @('Among Us', 'AmongUs')
    Stop-ProcessSafely -Names @('steam', 'steamwebhelper')

    New-Item -ItemType Directory -Path $SteamCmdRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ExtractPath -Force | Out-Null

    Write-Host '2/7 - SteamCMD letoltese...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SteamCmdUrl -OutFile $SteamCmdZip -UseBasicParsing

    if (-not (Test-Path -LiteralPath $SteamCmdZip -PathType Leaf)) {
        throw 'A SteamCMD ZIP letoltese sikertelen volt.'
    }

    Expand-Archive -LiteralPath $SteamCmdZip -DestinationPath $SteamCmdRoot -Force

    if (-not (Test-Path -LiteralPath $SteamCmdExe -PathType Leaf)) {
        throw 'A steamcmd.exe nem talalhato a kicsomagolas utan.'
    }

    Assert-AuthenticodePublisher -Path $SteamCmdExe -PublisherPattern '(?i)Valve'

    Write-Host '3/7 - Korabbi Among Us verzio letoltese a public-previous agrol...' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'A SteamCMD most Steam bejelentkezest ker.' -ForegroundColor Yellow
    Write-Host 'Add meg a jelszavadat es a Steam Guard kodot, amikor keri.' -ForegroundColor Yellow
    Write-Host 'A jelszo nem kerul bele ebbe a szkriptbe.' -ForegroundColor Yellow
    Write-Host ''

    $SteamUser = Read-Host 'Steam felhasznalonev'
    if ([string]::IsNullOrWhiteSpace($SteamUser)) {
        throw 'Nem adtal meg Steam felhasznalonevet.'
    }

    Push-Location $SteamCmdRoot
    try {
        & $SteamCmdExe `
            +force_install_dir $GamePath `
            +login $SteamUser `
            +app_update $AppId -beta $BetaBranch validate `
            +quit

        $steamCmdExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    # A SteamCMD egyes rendszereken sikeres telepites utan is adhat nem nulla
    # kilepesi kodot (peldaul 7-et) a leallaskor kiirt WorkThreadPool figyelmeztetes miatt.
    # Ezert nem csak a kilepesi kodot, hanem a tenylegesen telepitett jatekfajlokat is ellenorizzuk.
    $GameExe = Join-Path $GamePath 'Among Us.exe'
    $GameData = Join-Path $GamePath 'Among Us_Data'
    $UnityPlayer = Join-Path $GamePath 'UnityPlayer.dll'

    $installLooksValid =
        (Test-Path -LiteralPath $GameExe -PathType Leaf) -and
        (Test-Path -LiteralPath $GameData -PathType Container) -and
        (Test-Path -LiteralPath $UnityPlayer -PathType Leaf)

    if (-not $installLooksValid) {
        throw "A SteamCMD nem hozott letre ervenyes Among Us telepitest. Hibakod: $steamCmdExitCode; celmappa: $GamePath"
    }

    if ($steamCmdExitCode -ne 0) {
        Write-Host ("A SteamCMD {0} hibakoddal zart, de a jatek telepitese sikeresen ellenorizve lett. Folytatas..." -f $steamCmdExitCode) -ForegroundColor Yellow
    }
    else {
        Write-Host 'A korabbi Among Us verzio sikeresen telepult.' -ForegroundColor Green
    }

    Write-Host '4/7 - A legujabb Steam TOU Mira csomag keresese...' -ForegroundColor Cyan

    $headers = @{
        'User-Agent' = 'TOU-Mira-Steam-AllInOne-PowerShell-Installer'
        'Accept' = 'application/vnd.github+json'
    }

    $releases = Invoke-RestMethod -Uri $ReleasesApi -Headers $headers -Method Get
    $selected = $null

    foreach ($release in @($releases)) {
        if ($release.draft) {
            continue
        }

        $steamAssets = @($release.assets) |
            Where-Object {
                $_.name -match '(?i)\.zip$' -and
                $_.name -match '(?i)steam'
            }

        if (-not $steamAssets) {
            continue
        }

        $rankedAssets = foreach ($asset in $steamAssets) {
            $score = 0
            if ($asset.name -match '(?i)x64|64[-_ ]?bit') { $score += 100 }
            if ($asset.name -match '(?i)full|complete') { $score += 20 }
            if ($asset.name -match '(?i)win') { $score += 5 }

            [PSCustomObject]@{
                Asset = $asset
                Score = $score
            }
        }

        $bestAsset = $rankedAssets |
            Sort-Object Score -Descending |
            Select-Object -First 1

        if ($bestAsset) {
            $selected = [PSCustomObject]@{
                TagName = $release.tag_name
                Asset = $bestAsset.Asset
            }
            break
        }
    }

    if (-not $selected) {
        throw 'Nem talalhato Steamhez keszult ZIP-csomag a TOU Mira kiadasok kozott.'
    }

    Write-Host ("Kivalasztva: {0} - {1}" -f $selected.TagName, $selected.Asset.name) -ForegroundColor Green

    Write-Host '5/7 - TOU Mira letoltese es kicsomagolasa...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $selected.Asset.browser_download_url -OutFile $ModZip -UseBasicParsing

    if (-not (Test-Path -LiteralPath $ModZip -PathType Leaf)) {
        throw 'A TOU Mira ZIP letoltese sikertelen volt.'
    }

    if ((Get-Item -LiteralPath $ModZip).Length -lt 1024) {
        throw 'A letoltott mod ZIP tul kicsi, valoszinuleg hibas.'
    }

    Assert-GitHubAssetDigest -Asset $selected.Asset -Path $ModZip
    Expand-Archive -LiteralPath $ModZip -DestinationPath $ExtractPath -Force
    $ModSource = Find-ModSourceFolder -Root $ExtractPath

    Write-Host '6/7 - TOU Mira bemasolasa a Steam Among Us mappaba...' -ForegroundColor Cyan
    Copy-WithRobocopy -Source $ModSource -Destination $GamePath

    Write-Host '7/7 - A teljes modolt jatekmappa masolasa az Asztalra...' -ForegroundColor Cyan

    if (Test-Path -LiteralPath $DesktopTarget) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = Join-Path $DesktopPath ("Among Us - TOU Mira - regi-$timestamp")
        Write-Host ("A korabbi asztali mappa atnevezese erre: {0}" -f $backupPath) -ForegroundColor Yellow
        Move-Item -LiteralPath $DesktopTarget -Destination $backupPath
    }

    Copy-WithRobocopy -Source $GamePath -Destination $DesktopTarget

    Write-Host ''
    Write-Host 'KESZ.' -ForegroundColor Green
    Write-Host ("Korabbi Steam verzio + mod: {0}" -f $GamePath) -ForegroundColor Green
    Write-Host ("Asztali TOU Mira masolat:    {0}" -f $DesktopTarget) -ForegroundColor Green
    Write-Host ''
    Write-Host 'Az asztali Among Us - TOU Mira mappabol inditsd az Among Us.exe fajlt.' -ForegroundColor Yellow
    Write-Host 'A Steam kliens kesobb frissitheti a sajat telepitett peldanyat, de az asztali masolatot nem.' -ForegroundColor Yellow
}
catch {
    Write-Host ''
    Write-Host 'Hiba tortent:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Read-Host 'Nyomj Entert a bezarashoz'
