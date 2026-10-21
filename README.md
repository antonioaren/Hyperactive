# Hyperactive

A lightweight macOS menu bar app that helps keep your Mac awake by periodically nudging the mouse cursor.

Inspired by utilities like Caffeine, Hyperactive is designed for moments when you want your Mac to remain active during long-running tasks, reading sessions, downloads, renders, monitoring dashboards, or other periods where you may not be touching the keyboard or mouse. Instead of only preventing sleep through system assertions, Hyperactive performs a tiny cursor movement and then moves it back.

## How It Works

Hyperactive sits in your menu bar and moves the mouse cursor by a few pixels (±2-4px) at a configurable interval, then moves it back. The movement is intentionally small so it helps keep the system active without disrupting normal mouse usage.

## Features

- **One-click toggle** from the menu bar
- **Visual indicator** — icon changes when active (`cursorarrow.motionlines` vs `cursorarrow`)
- **Configurable interval** — 1, 2, 5, 10, 15, or 30 minutes
- **Nudge counter** — see how many nudges have occurred and when
- **Launch at Login** — start automatically with macOS
- **Keep awake with the lid closed** — stays awake with no external display, so a local AI job keeps running
- **In-app updates** — shows the installed version and offers a one-click update when a new release is out
- **Invisible** — no Dock icon, no Cmd-Tab entry
- **Lightweight** — native Swift, ~3 MB, negligible CPU

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (the app will prompt you)

## Install

### From Release

1. Download `Hyperactive-X.Y.Z.dmg` from the [latest release](https://github.com/antonioaren/Hyperactive/releases/latest)
2. Open it and drag `Hyperactive.app` to `/Applications`
3. Launch — if you see a Gatekeeper warning, right-click > Open
4. Grant Accessibility access when prompted

Every release also includes `Hyperactive-X.Y.Z-macOS.zip` (the zipped app, Apple silicon + Intel) and `Hyperactive-X.Y.Z-source.zip` (the source code).

### Updating

The menu shows the installed version (`Version X.Y.Z (build N)`). Hyperactive checks GitHub Releases at launch and once a day. When a newer version exists, the menu shows **Update to vX.Y.Z**: click it to download the new app, replace the installed copy and relaunch. You can also click **Check for Updates…** at any time.

- Run Hyperactive from `/Applications`. Updating does not work while it runs from the DMG or the Downloads folder.
- If the app folder is not writable by your user, macOS asks for an administrator password.
- Release builds are ad-hoc signed unless Developer ID signing is configured (see below), so macOS may ask you to grant Accessibility access again after an update.

### Build from Source

```bash
# Clone
git clone <repo-url>
cd hyperactive

# Build (requires Xcode 15+)
make release

# Or open in Xcode
make open
```

The built app will be in `build/Build/Products/Release/Hyperactive.app`.

Other targets:

```bash
make release VERSION=1.2.0 BUILD_NUMBER=7   # embed a specific version
make dmg                                    # build + build/dist/Hyperactive-<version>.dmg
make zip                                    # build + build/dist/Hyperactive-<version>-macOS.zip
make source-zip                             # build/dist/Hyperactive-<version>-source.zip
```

Without `VERSION`, local builds use the latest `vX.Y.Z` git tag.

## Versioning & Releases

Every push to `main` publishes a new [GitHub Release](https://github.com/antonioaren/Hyperactive/releases) through [`.github/workflows/release.yml`](.github/workflows/release.yml). Pull requests run the same build without publishing, so a broken build shows up before merge.

The version is the git tag `vMAJOR.MINOR.PATCH`. [`scripts/next-version.sh`](scripts/next-version.sh) picks the next one from the [Conventional Commits](https://www.conventionalcommits.org/) since the last tag:

| Commit message | Bump | Example |
| --- | --- | --- |
| `feat!: …` / `fix(scope)!: …` or a `BREAKING CHANGE:` footer | major | 1.4.2 → 2.0.0 |
| `feat: …` / `feat(scope): …` | minor | 1.4.2 → 1.5.0 |
| anything else (`fix:`, `docs:`, plain messages) | patch | 1.4.2 → 1.4.3 |

The first release is `v1.0.0`. To merge without releasing, put `[skip release]` in the merge (or squash) commit message.

Each release contains:

- Release notes from [`scripts/release-notes.sh`](scripts/release-notes.sh): a short summary and the commits since the previous release, grouped into breaking changes, new features, bug fixes and other changes.
- `Hyperactive-X.Y.Z.dmg` and `Hyperactive-X.Y.Z-macOS.zip`: the universal app. The in-app updater downloads the zip.
- `Hyperactive-X.Y.Z-source.zip`, plus the source archives GitHub attaches to every release.

### Optional: Developer ID signing and notarization

By default the app is ad-hoc signed. To sign with a Developer ID certificate and notarize, add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64 of the exported "Developer ID Application" `.p12` |
| `MACOS_CERTIFICATE_PWD` | Password of that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |

With only the certificate secrets the app is signed but not notarized. A stable Developer ID signature also keeps the Accessibility permission across updates.

## Permissions

Hyperactive needs **Accessibility** permission to move the mouse cursor.

On first launch (or when you click "Start"), macOS will prompt you to grant access:

**System Settings > Privacy & Security > Accessibility > Hyperactive** — toggle ON.

If you miss the prompt, click **"Grant Accessibility Access..."** in the app's menu.

**Keep Awake with Lid Closed** also needs an administrator password. macOS sleeps a laptop immediately when the lid closes and no external display is attached; cursor nudges cannot block that. The menu item runs `pmset -a disablesleep` and restores normal sleep when you turn it off or quit. The built-in panel turns off with the lid. The Mac, and anything running on it, stays awake.

That runs hot. Don't put the Mac in a bag. If the app quits uncleanly and the Mac never sleeps again, run:

```bash
sudo pmset -a disablesleep 0
```

## Usage

1. Click the cursor icon in the menu bar
2. Click **Start** — the icon changes to show motion lines
3. The mouse will nudge every 5 minutes (default)
4. To change the interval: **Interval >** submenu
5. Click **Stop** to deactivate
6. To keep a local job running with the lid shut and no external display, turn on **Keep Awake with Lid Closed** before you close the lid, then enter your password

## Menu

```
Start / Stop              ⌘S
─────────────────────────────
Active — 12 nudges (last: 2:34 PM)
─────────────────────────────
Interval ▸ [1, 2, 5✓, 10, 15, 30 min]
─────────────────────────────
☑ Launch at Login
─────────────────────────────
☐ Keep Awake with Lid Closed
No external display — closing the lid would normally sleep this Mac.
Runs hot with the lid closed. Don't put the Mac in a bag.
─────────────────────────────
Version 1.2.0 (build 42)
Update to v1.3.0 / Check for Updates…
─────────────────────────────
About Hyperactive
Quit                      ⌘Q
```

## Original Script

The original command-line version is preserved as `keep_active.py`:

```bash
python3 keep_active.py -t 5   # Nudge every 5 minutes
```

## License

MIT
