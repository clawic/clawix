# Windows scripts

PowerShell counterparts of `macos/scripts/*.sh`.

| Script | Equivalent | Purpose |
|---|---|---|
| `dev.ps1` | `dev.sh` | Build + kill prev + relaunch with the right `.app-mode` |
| `build-app.ps1` | `build_app.sh` | Core dotnet build + optional signtool |
| `build-release.ps1` | `build_release_app.sh` | Release: dotnet publish, sign, MSIX pack |
| `public_hygiene_check.ps1` | `public_hygiene_check.sh` | Forbidden literal scan |
| `_emit_version.ps1` | `_emit_version.sh` | Read VERSION + BUILD_NUMBER |

All scripts read `.signing.env` from the workspace root for
`WIN_SIGN_THUMBPRINT`, `WIN_SIGN_TIMESTAMP_URL`, etc. The values never
appear in code or in the public repo.
