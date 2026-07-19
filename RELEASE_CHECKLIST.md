# Release checklist

Use a unique versioned tag such as `installer-v1.1.0`. Do not reuse or move an old tag.

## Before creating the release

- [ ] Commit both complete PowerShell installers under `scripts/`.
- [ ] Review every changed URL and all process execution, elevation, file-copy, and deletion operations.
- [ ] Confirm that both installers still show the disclaimer and require `ELFOGADOM`.
- [ ] Confirm that the Steam installer works both as a local file and through `iwr | iex` with UAC elevation.
- [ ] Confirm that the Epic installer works both as a local file and through `iwr | iex` as a normal user.
- [ ] Confirm the pinned Epic downgrader SHA-256 is correct for the intended release.
- [ ] Verify that the SteamCMD Authenticode publisher check succeeds.
- [ ] Test cancellation, network failure, invalid digest, and cleanup paths.
- [ ] Test both installers in disposable clean Windows virtual machines.
- [ ] Test the uninstall and restore instructions.

## Publishing

1. Create a **draft** GitHub release.
2. Upload the two exact files from `scripts/` as release assets.
3. Publish the release.
4. Confirm that the release workflow uploads `SHA256SUMS.txt`.
5. Compare GitHub's displayed SHA-256 values with `SHA256SUMS.txt`.
6. Deploy the same two committed files to the `matyusb.org` endpoints.
7. Run `scripts/Test-WebEndpoints.ps1` and require both endpoint hashes to match.
8. Test both public one-line commands in disposable Windows virtual machines.

## Release description template

````markdown
## Important notice

Unofficial community installer provided as-is. It modifies game files and downloads third-party components. There is no paid support, warranty, maintenance guarantee, or compatibility guarantee. It is not affiliated with Innersloth, Valve, Steam, Epic Games, Microsoft, AU Avengers, or the third-party tool authors.

### Quick commands

```powershell
iwr "https://matyusb.org/steam" -UseBasicParsing | iex
iwr "https://matyusb.org/epicgames" -UseBasicParsing | iex
```

These commands execute the current complete installer returned by `matyusb.org`. Users who do not want to execute remote code directly should download the matching release asset, verify it with `SHA256SUMS.txt`, review it, and run it locally.

### Assets

- `TOU-Mira-Telepito-Steam.ps1` — Steam installer
- `TOU-Mira-Telepito-Epic-Games.ps1` — Epic Games installer
- `SHA256SUMS.txt` — checksums

### Known trust boundary

The Epic path executes a checksum-pinned external downgrader, but that downgrader makes additional third-party downloads. Review `DEPENDENCIES.md` before running it.
````
