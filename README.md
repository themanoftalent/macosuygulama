<div align="center">

# macOS Uygulama

Native, local-first, open-source apps for macOS.

[Website](https://macosuygulama.vercel.app) · [Türkçe](https://macosuygulama.vercel.app/tr/) · [Report an issue](https://github.com/themanoftalent/macosuygulama/issues) · [Contribute](CONTRIBUTING.md)

![Vercel](https://img.shields.io/badge/deployed%20on-Vercel-000?logo=vercel)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Apps](https://img.shields.io/badge/apps-9-blue)
![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

</div>

macOS Uygulama is the home page and download hub for a family of macOS tools built and maintained by Mehmet Akif Çifçi ([@themanoftalent](https://github.com/themanoftalent)). Every app runs on your machine, needs no account, and ships its source code on GitHub.

This repository holds the website only. Each app lives in its own repository, linked below.

## Apps

| App | What it does | Stack | Latest | License |
|---|---|---|---|---|
| [PdfAle](https://github.com/themanoftalent/pdfale) | PDF editing, annotation, page organizing, form filling and signing | Rust, egui | [![release](https://img.shields.io/github/v/release/themanoftalent/pdfale?label=)](https://github.com/themanoftalent/pdfale/releases/latest) | MIT OR Apache-2.0 |
| [Temizale](https://github.com/themanoftalent/Temizale) | Cache and Trash cleaning, orphaned file scrubbing, app uninstalling | Swift 6, SwiftUI | [![release](https://img.shields.io/github/v/release/themanoftalent/Temizale?label=)](https://github.com/themanoftalent/Temizale/releases/latest) | see repo |
| [Miknatizale](https://github.com/themanoftalent/Miknatizale) | Window snapping to halves, thirds and quadrants | Swift 6, AppKit | [![release](https://img.shields.io/github/v/release/themanoftalent/Miknatizale?label=)](https://github.com/themanoftalent/Miknatizale/releases/latest) | see repo |
| [RecordAle](https://github.com/themanoftalent/RecordAle) | Screen recording for walkthroughs with auto zoom and cursor smoothing | TypeScript, Motion Canvas | [![release](https://img.shields.io/github/v/release/themanoftalent/RecordAle?label=)](https://github.com/themanoftalent/RecordAle/releases/latest) | see repo |
| [Foldale](https://github.com/themanoftalent/foldale) | Dual-pane, keyboard-driven file manager | TypeScript, Rust | [![release](https://img.shields.io/github/v/release/themanoftalent/foldale?label=)](https://github.com/themanoftalent/foldale/releases/latest) | see repo |
| [Saklamac Pro](https://github.com/themanoftalent/saklamac) | Notch-safe menu bar item manager with an overflow shelf | Swift 6, SwiftUI | source only | MIT |
| [Clipale](https://github.com/themanoftalent/clipale) | Clipboard history with search, instant paste, bulk delete, Google Drive week folders and Mac–iPhone sync | Swift 6, AppKit | [![release](https://img.shields.io/github/v/release/themanoftalent/clipale?label=)](https://github.com/themanoftalent/clipale/releases/latest) | see repo |
| [AleBar](https://github.com/themanoftalent/AleBar) | Menu bar organizer, styling and command palette | Swift 6 | [![release](https://img.shields.io/github/v/release/themanoftalent/AleBar?label=)](https://github.com/themanoftalent/AleBar/releases/latest) | MIT |
| [AleDesk](https://github.com/themanoftalent/AleDesk) | Remote desktop control and file transfer for macOS and Windows | Rust, Flutter | source only | AGPL-3.0 |
| [DesktopDüzen](apps/DesktopDuzen) | Desktop zone organizer (Stardock Fences style) with live sync, auto-sort & widgets | Swift 6, AppKit, SwiftUI | [DMG (v1.1.0)](apps/DesktopDuzen/DesktopDuzen.dmg) | MIT |

Clipale also has companion clients for [iOS](https://github.com/themanoftalent/clipale-ios), [Windows](https://github.com/themanoftalent/clipale-windows) and [Android](https://github.com/themanoftalent/clipale-android).

## Design principles

1. Native first. Swift for Apple frameworks, Rust where performance or portability matters. Builds target Apple Silicon and Intel.
2. Local by default. Your files and clipboard stay on your Mac. No telemetry, no sign-in.
3. Follows the macOS Human Interface Guidelines, so the apps behave like the rest of your system.
4. Small footprint. Background helpers stay light on memory and battery.
5. Scriptable. Where it makes sense, apps expose a CLI or a Model Context Protocol (MCP) interface.

## Built on open source

Two of these apps start from established open-source projects. Their authors did the foundational work, and their licenses travel with the code.


If you contributed to one of these upstream projects, thank you. Open an issue if you want your name listed here.

## Repository layout

```
dist/        static site (English at /, Turkish at /tr/)
  assets/    icons, screenshots
  locale.js  language switching
api/         Vercel serverless functions
scripts/     build and maintenance scripts
tools/       helper tooling
vercel.json  deployment config
```

## Run the site locally

```bash
git clone https://github.com/themanoftalent/macosuygulama.git
cd macosuygulama
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open http://127.0.0.1:4173/ for English or http://127.0.0.1:4173/tr/ for Turkish.

## Deployment

Vercel deploys every push to `main`.

| Setting | Value |
|---|---|
| Production URL | [macosuygulama.vercel.app](https://macosuygulama.vercel.app) |
| Framework preset | Other (static) |
| Output directory | `dist` |

## Contributing

You can help in four ways, and none of them need Swift or Rust:

1. Fix a typo or improve the wording on the site, in English or Turkish.
2. Translate the site into another language.
3. Add screenshots or short demo GIFs for an app.
4. Report a broken link or download.

Bugs and feature requests for a specific app go to that app's repository. Read [CONTRIBUTING.md](CONTRIBUTING.md) before you open a pull request.

## Author

Mehmet Akif Çifçi · [GitHub](https://github.com/themanoftalent) · [ORCID](https://orcid.org/0000-0002-6439-8826)

If an app saves you time, star its repository. That helps other Mac users find it.
