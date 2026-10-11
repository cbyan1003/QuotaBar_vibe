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

The menu-bar icon stays up. Click it for the quota panel. A Dock icon appears only while a main window, such as Settings or a share card, is open. Command-Q quits the app. Command-W closes the current window. A second launch brings the existing app forward instead of starting another copy.

## What it shows

The panel lists the providers you turn on. Each card shows the plan, the remaining quota, and when that window resets. Codex cards also list every account saved in QuotaBar. A row shows, in order, how long until the quota resets, how much is left, and how many banked resets remain. Switching an account rewrites the Codex CLI sign-in. Sessions that are already running keep the old account until they are restarted.

Codex and Claude can each store a relay address and key in Settings. QuotaBar asks that station for the remaining balance and shows it on the card. It does not change which account the CLI is using.

## Usage

Settings → Usage reads local session logs and builds a year heatmap. The sources are Codex, Claude Code, and Cursor. Cursor comes from the account signed in on this Mac and is cached locally.

Click a day on the heatmap. The model list under the grid reorders to that day's usage, largest first. Click the same day again and the list returns to the whole year. Click a model row to show that model alone on the grid.

## Settings

The sidebar in this copy is:

- **Providers.** Which services to track, how each one signs in, and the relay address and key for Codex and Claude. Saved Codex sign-ins stay in this Mac's keychain.
- **Usage.** The year heatmap and the totals behind it.
- **Projects.** Where the tokens went, by repository and tool.
- **Service status.** What each provider's public status page says.
- **Appearance.** The menu-bar icon and what it counts.
- **Presentation.** Where the numbers appear besides the menu bar. The menu panel uses Liquid Glass, with a dark wash so the figures stay readable.
- **Alerts.** When to be told a limit is getting close.
- **General.** Language, refresh interval, and stored history.
- **About.** Version, the original QuotaBar credit, and what this copy does with data.

Quota Run, the iPhone companion, feedback, and in-app updates are not part of this copy.

Keys and saved sign-ins are not in this repository. They stay in the keychain on the Mac that created them. The first time this build reads an item, macOS may ask once. Later refreshes in the same launch reuse that answer.

## Build

macOS 14 or later. This copy is built and used on Apple Silicon. You need either full Xcode, or Command Line Tools new enough to include the macOS 26 SDK (the 26.2 tools are known to work). Older Command Line Tools stop at the macOS 15 SDK and cannot compile Liquid Glass.

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
