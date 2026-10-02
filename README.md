# Buddi — personal fork

A macOS notch companion for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — a fork of [talkvalue/Buddi](https://github.com/talkvalue/Buddi) that shows GLM Coding Plan (Z.ai) usage quotas in the notch.

## What changed vs upstream

- **GLM Coding Plan quota widget** — reads `ANTHROPIC_AUTH_TOKEN` from the `env` block of `~/.claude/settings.json` and calls the Z.ai monitor API (`/api/monitor/usage/quota/limit`) to display your quota. Falls back to Claude Code's Anthropic OAuth if no key is present.
- **Rebranded identities** — so this fork coexists with the official app:
  - Bundle ID: `com.cocoryse.buddi`
  - Hook socket: `/tmp/buddi-cocoryse.sock`
  - Hook script: `~/.claude/hooks/buddi-cocoryse-hook.py`
- **Sparkle auto-update removed** — to update, `git pull` and rebuild.
- **Release workflow removed** — this repo publishes no signed binaries or tags.

## Requirements

- macOS 15.0+ (Sequoia)
- MacBook with a notch
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A Z.ai GLM Coding Plan key set as `ANTHROPIC_AUTH_TOKEN` in the `env` block of `~/.claude/settings.json`

## Build

```bash
git clone git@github.com:CocoRyse/Buddi.git
cd Buddi
xcodebuild -resolvePackageDependencies -scheme buddi
xcodebuild build -scheme buddi -destination 'platform=macOS' -configuration Debug
```

Or open `buddi.xcodeproj` in Xcode, select the **buddi** scheme, and press ⌘R. SPM dependencies resolve automatically on first build.

There are no binary releases and no Homebrew cask for this fork — build from source.

## Credits & license

- Fork of [talkvalue/Buddi](https://github.com/talkvalue/Buddi)
- Buddi builds on [boring.notch](https://github.com/TheBoredTeam/boring.notch) and [Claude Island](https://github.com/farouqaldori/claude-island)
- Licensed under the [GNU General Public License v3](LICENSE) — see [NOTICE](NOTICE) for full attribution.
