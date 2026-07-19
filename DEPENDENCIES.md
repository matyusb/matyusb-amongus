# External dependencies and trust boundaries

The installers are only orchestration scripts. They do not contain the game or the TOU Mira mod.

## Shared dependency

### AU Avengers / TOU Mira

- API: `https://api.github.com/repos/AU-Avengers/TOU-Mira/releases`
- Purpose: finds a compatible Steam or Epic/MS Store ZIP.
- Selection: newest non-draft release matching the expected platform naming.
- Verification: the downloaded ZIP must match the release asset's GitHub `sha256:` digest.
- Remaining risk: an upstream account or release can intentionally publish a malicious file with a matching digest. A checksum proves integrity, not trustworthiness.

## Steam installer

### SteamCMD

- URL: `https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip`
- Purpose: downloads the `public-previous` Among Us branch.
- Verification: after extraction, the installer requires a valid Windows Authenticode signature whose publisher contains `Valve`.
- Privilege: the Steam installer elevates because the default Steam game directory is under Program Files.
- Authentication: the script asks only for the Steam username. SteamCMD itself requests password and Steam Guard information.

## Epic Games installer

### EpicGamesDowngrader

- URL: `https://github.com/whichtwix/EpicGamesDowngrader/releases/download/2026.3.31/DowngradeEpic.ps1`
- Expected SHA-256: `effbae48554296e2999a3864b0eeb666584d83bae34fbb42d604d0a89d236a11`
- Purpose: downloads an older compatible Epic Games build.
- Execution: the downloaded script is run only after the pinned checksum matches.

### Nested downloads made by EpicGamesDowngrader

The pinned downgrader currently downloads additional components, including a modified Legendary client, an Among Us manifest, and EpicGamesStarter. Some of those downloads use `latest` URLs and are not independently pinned by this repository.

This is the largest remaining supply-chain risk. The installer displays this fact before execution. Fully removing it would require vendoring or reimplementing the downgrader and maintaining fixed hashes for all nested files.

## Local changes

The scripts may:

- Stop Among Us, Steam, and related launcher processes.
- Download game and mod files.
- Modify or create an Among Us installation folder.
- Create a separate desktop copy named `Among Us - TOU Mira`.
- Rename a previous desktop copy with a timestamp.
- Request administrator privileges for Program Files or folder-permission changes.
- Remove temporary installer files after completion.
