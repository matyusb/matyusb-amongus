# Website installer endpoints

The public commands remain:

```powershell
iwr "https://matyusb.org/steam" -UseBasicParsing | iex
iwr "https://matyusb.org/epicgames" -UseBasicParsing | iex
```

## Required endpoint behavior

The two URLs must return the **complete installer source**, not HTML, a landing page, or a small bootstrap script:

- `/steam` returns the exact bytes of `scripts/TOU-Mira-Telepito-Steam.ps1`.
- `/epicgames` returns the exact bytes of `scripts/TOU-Mira-Telepito-Epic-Games.ps1`.

Recommended HTTP behavior:

- HTTPS only.
- `Content-Type: text/plain; charset=utf-8`.
- `X-Content-Type-Options: nosniff`.
- `Cache-Control: no-cache` or a similarly revalidation-focused policy.
- No advertisements, injected banners, analytics code, HTML wrappers, or other text in the response body.
- Return a non-success status on errors; never return an HTML error page with status 200.

A redirect is acceptable only when the final response is the exact versioned `.ps1` installer text. Do not redirect to a GitHub HTML release page.

## Deployment rule

Deploy the exact scripts that were committed and uploaded to the corresponding GitHub release. Do not edit the website copies by hand.

After deploying, run:

```powershell
.\scripts\Test-WebEndpoints.ps1
```

The test downloads both public endpoints, parses them as PowerShell, and compares their SHA-256 hashes with the committed files. A mismatch means the website is not serving the reviewed installers.

Use a new versioned release tag for every installer change. Never silently replace an installer under an old release tag.
