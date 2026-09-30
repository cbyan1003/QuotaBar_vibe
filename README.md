<div align="center">

<img src="Assets/icon.png" alt="QuotaBar" width="112" height="112">

# QuotaBar_vibe

**A derivative of [QuotaBar](https://github.com/QuotaBar/QuotaBar), maintained by bobo.**

This repository is [cbyan1003/QuotaBar_vibe](https://github.com/cbyan1003/QuotaBar_vibe).
It is not the upstream project, not quota.bar, and not distributed through the original Homebrew tap.

[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## What this is

[QuotaBar](https://github.com/QuotaBar/QuotaBar) (copyright GiantAccel, LLC, MIT) is a macOS menu-bar app that shows AI coding quotas. This copy starts from that source and is developed further by bobo.

Kept from the original: local quota readings for the providers you turn on, and usage totals from this Mac's Codex and Claude Code session logs.

Changed in this copy:

- Cursor usage is included in the usage page. It is read from the signed-in Cursor account and cached on this Mac.
- Codex and Claude each have a relay URL and key in Settings. QuotaBar asks that station for the account balance. It does not switch which account the CLI uses.
- The menu-bar icon stays. A Dock icon appears only while a main window (Settings, share card) is open.
- Quota Run, the iPhone companion, feedback, and in-app updates are not part of this copy.

## Build

macOS 14 or later. Apple Silicon is what this copy is built and used on. You need either full Xcode, or Command Line Tools new enough to include the macOS 26 SDK (the 26.2 tools are known to work). Older Command Line Tools stop at the macOS 15 SDK and cannot compile Liquid Glass.

```bash
git clone https://github.com/cbyan1003/QuotaBar_vibe.git
cd QuotaBar_vibe
UNIVERSAL=0 ./Scripts/package_app.sh
open QuotaBar.app
```

`UNIVERSAL=0` builds the current Mac only. Omit it to also build the Intel slice. The script signs ad-hoc when no Developer ID certificate is present, so the app runs on this Mac only.

There is no release download and no Homebrew formula for this repository. Clone it and compile it.

## License

MIT. The original copyright is GiantAccel, LLC. See [LICENSE](LICENSE).
This derivative does not replace that notice.
