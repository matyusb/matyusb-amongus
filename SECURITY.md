# Security policy

## Important limitations

The recommended one-line commands use `Invoke-Expression` to execute the current response from `matyusb.org`. This means the initial installer source cannot verify itself before execution. Users must trust the domain, DNS, HTTPS/TLS path, hosting account, and deployment process.

The scripts are not Authenticode-signed because a trusted commercial code-signing certificate is not available for this free project. Checksums are still published for users who download the release files manually.

A correct SHA-256 checksum confirms that a downloaded file matches the published release asset. It does not prove that the code is harmless.

## Risk-reduction measures

- Keep the domain registrar, DNS provider, hosting account, GitHub account, and email account protected with unique passwords and multi-factor authentication.
- Use the least-privileged deployment credential possible.
- Serve only the exact committed installer bytes from the short URLs.
- Require review before every deployment.
- Publish a new release tag for each change rather than replacing old assets.
- Run `scripts/Test-WebEndpoints.ps1` after every website deployment.
- Keep third-party URLs pinned and verify hashes or signatures whenever upstream data makes that possible.

## Supported release

Only the newest published installer release is intended for use. Older releases may contain outdated dependency URLs or checksums. Support, response times, fixes, ongoing maintenance, and future compatibility are not guaranteed.

## Reporting a security problem

Do not include passwords, authorization codes, account tokens, cookies, or personal information in a report.

Prefer GitHub's private vulnerability reporting feature when it is enabled. Otherwise, open a minimal public issue stating that a security problem exists without publishing exploit details or secrets.

## Maintainer checklist

Before publishing:

1. Review every changed URL and downloaded file.
2. Run PowerShell syntax and static-analysis checks on a clean Windows machine.
3. Test both local-file and `iwr | iex` execution paths in disposable Windows virtual machines.
4. Upload the exact scripts committed in `scripts/`.
5. Generate and verify `SHA256SUMS.txt`.
6. Deploy those exact files to `matyusb.org`.
7. Confirm the public endpoint hashes match the repository files.
8. Never replace assets inside an existing published version.
