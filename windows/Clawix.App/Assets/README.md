# Assets

Binary assets must be regenerated locally; they are not in this folder
because checked-in PNGs and ICO files would balloon the repo. Drop the
following before building a release MSIX:

| File | Required by | How to generate |
|---|---|---|
| `Clawix.ico` | `Clawix.App.csproj` (`<ApplicationIcon>`) | Convert `clawix/brand/icon.svg` to multi-resolution `.ico` (16/32/48/64/128/256). Tools: ImageMagick (`magick convert icon.svg -define icon:auto-resize=256,128,64,48,32,16 Clawix.ico`) |
| `StoreLogo.png` | `Package.appxmanifest` | 50x50 PNG of the app icon |
| `Square150x150Logo.png` | `Package.appxmanifest` | 150x150 PNG |
| `Square44x44Logo.png` | `Package.appxmanifest` | 44x44 PNG |
| `Wide310x150Logo.png` | `Package.appxmanifest` | 310x150 PNG |
| `SplashScreen.png` | `Package.appxmanifest` | 620x300 PNG |

Source artwork lives in `clawix/brand/`. The same SVG that produces
`macos/.../AppIcon.appiconset/...` produces these. Do not bake brand
elements into the build pipeline; render once before
`scripts\build-release.ps1`.
