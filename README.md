# TOU Mira installer helpers

Unofficial community installers for setting up the **Town of Us: Mira** mod with the Steam or Epic Games edition of Among Us.

> [!WARNING]
> These commands download the current PowerShell installer from `matyusb.org` and execute it immediately. Only use them if you trust that domain and have reviewed the source. The installers modify game files, stop game or launcher processes, download third-party software, and may request administrator privileges.

## Quick installation

Run only the command matching your game edition:

```powershell
# Epic Games
iwr "https://matyusb.org/epicgames" -UseBasicParsing | iex

# Steam
iwr "https://matyusb.org/steam" -UseBasicParsing | iex
```

The two short URLs return the **complete installer scripts**, not a bootstrap loader. Each installer shows a warning and requires the user to type `ELFOGADOM` before changing game files.

The Steam installer requests administrator privileges because the default game directory is under `Program Files`. When started through `iwr | iex`, it opens an elevated PowerShell process and retrieves the same full Steam installer URL again. The Epic installer should be started as a normal user and requests elevation only if it must repair the permissions of the Games directory.

## Project status and disclaimer

This project is free, community-created, and provided as-is. It has no paid support, financial support commitment, warranty, uptime promise, maintenance guarantee, or guarantee of compatibility. Development may stop at any time.

It is not affiliated with, endorsed by, or supported by Innersloth, Valve, Steam, Epic Games, Microsoft, AU Avengers, or the authors of the third-party tools it downloads.

Game updates, launcher updates, antivirus changes, website compromise, DNS compromise, TLS-certificate compromise, or upstream release changes can break the installers or change their risk. Users are responsible for deciding whether to run them and for any changes made to their computer or game installation.

Never enter a password directly into either PowerShell script. Steam credentials are requested by SteamCMD. Epic authentication is handled by the external Epic/Legendary authentication flow.

## Review and verify before running

Users who prefer to inspect the installer should download it without executing it:

```powershell
# Steam
Invoke-WebRequest "https://matyusb.org/steam" -UseBasicParsing -OutFile .\TOU-Mira-Telepito-Steam.ps1

# Epic Games
Invoke-WebRequest "https://matyusb.org/epicgames" -UseBasicParsing -OutFile .\TOU-Mira-Telepito-Epic-Games.ps1
```

Then compare its SHA-256 value with the matching GitHub release asset and `SHA256SUMS.txt`:

```powershell
Get-FileHash .\TOU-Mira-Telepito-Steam.ps1 -Algorithm SHA256
```

After review, run the local file:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TOU-Mira-Telepito-Steam.ps1
```

## What the hardened scripts verify

- The downloaded TOU Mira ZIP must match the SHA-256 digest returned by GitHub's release API.
- The Epic downgrader is pinned to release `2026.3.31` and must match its expected SHA-256 checksum.
- The Steam installer checks the Authenticode signature on `steamcmd.exe` and requires a Valve publisher certificate.
- The release workflow generates `SHA256SUMS.txt` for the installer release assets.

These checks reduce supply-chain risk after the installer starts. They cannot verify the initial `matyusb.org | iex` download, because PowerShell executes that response before the installer can verify itself. See [DEPENDENCIES.md](DEPENDENCIES.md) and [SECURITY.md](SECURITY.md).

## Repository layout

- `scripts/TOU-Mira-Telepito-Steam.ps1` — complete Steam installer
- `scripts/TOU-Mira-Telepito-Epic-Games.ps1` — complete Epic Games installer
- `scripts/Test-InstallerHash.ps1` — release checksum verifier
- `scripts/Test-WebEndpoints.ps1` — confirms that both public URLs exactly match the committed installers
- `.github/workflows/release-checksums.yml` — generates release checksums
- `DEPENDENCIES.md` — external downloads and permissions
- `SECURITY.md` — security limitations and reporting information
- `RELEASE_CHECKLIST.md` — publishing and testing steps
- `WEBSITE.md` — how the two installer endpoints should behave
- `UNINSTALL.md` — restoration instructions
