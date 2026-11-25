# Hyperactive

A lightweight macOS menu bar app that helps keep your Mac awake by periodically nudging the mouse cursor.

Inspired by utilities like Caffeine, Hyperactive is designed for moments when you want your Mac to remain active during long-running tasks, reading sessions, downloads, renders, monitoring dashboards, or other periods where you may not be touching the keyboard or mouse. Instead of only preventing sleep through system assertions, Hyperactive performs a tiny cursor movement and then moves it back.

## How It Works

Hyperactive sits in your menu bar and moves the mouse cursor by a few pixels (±2-4px) at a configurable interval, then moves it back. The movement is intentionally small so it helps keep the system active without disrupting normal mouse usage.

**Snooze** limits that to the hours you choose. Each weekday has its own windows. Inside a window the pointer moves and the display stays awake. Outside them, Hyperactive either does nothing or keeps the display awake without moving the pointer. Snooze is off until you turn it on, so the app behaves as before until then. The interval is one of 1, 2, 5, 10, 15, or 30 minutes and is remembered; a missing or invalid saved value is 5 minutes.

## Features

- **One-click toggle** from the menu bar
- **Snooze** — per-weekday active hours, with an optional weekdays-only switch. Outside those hours, stop completely or keep the display on without moving the pointer
- **Visual indicator** — icon changes when nudging (`cursorarrow.motionlines`), keeping the display on (`display`), snoozed (`moon.zzz`), or off (`cursorarrow`)
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
- Release builds are ad-hoc signed unless a stable signing certificate is configured (see below). An ad-hoc signature changes every version, so macOS asks for Accessibility access again after an update.

### Build from Source

```bash
# Clone
git clone <repo-url>
cd hyperactive

# Build (requires Xcode 15+)
make release

# Or open in Xcode
make open

# Schedule unit tests
make test
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

### Optional: stable self-signed certificate

Use this when you do not have an Apple Developer account and you still want Accessibility to survive updates. macOS ties an ad-hoc signature to that build's cdhash, so each release looks like a different app. A certificate you create once and reuse has a constant designated requirement, and the Accessibility grant stays with that requirement.

Trade-offs:

| | Developer ID + notarization | Stable self-signed certificate | Ad-hoc (no secret) |
| --- | --- | --- | --- |
| Accessibility across updates | Kept | Kept, after one approval of this certificate | Asked again every update |
| Gatekeeper | Quiet after notarization | Still warns. Right-click the app and choose Open the first time | Still warns |
| Apple Developer account | Required | Not required | Not required |
| What you must keep | The Developer ID `.p12` | The same self-signed `.p12`. A new certificate starts the problem over | Nothing |

Developer ID wins when `MACOS_CERTIFICATE` is set. Otherwise CI uses `HYPERACTIVE_SIGNING_CERTIFICATE` if that secret is set. With neither secret, the build stays ad-hoc.

Create the certificate once, on any machine with OpenSSL, and do not commit the `.p12`:

```bash
HYPERACTIVE_SIGNING_CERTIFICATE_PWD='choose-a-password' \
  scripts/create-signing-certificate.sh
```

Add these repository secrets (Settings > Secrets and variables > Actions):

| Secret | Value |
| --- | --- |
| `HYPERACTIVE_SIGNING_CERTIFICATE` | Base64 printed by the script |
| `HYPERACTIVE_SIGNING_CERTIFICATE_PWD` | The password you set |

The first release signed with that certificate still needs Accessibility removed and added once. Later releases signed with the same certificate keep the grant. Confirm the requirement did not change with `codesign -d -r- /Applications/Hyperactive.app`.

## Permissions

Hyperactive needs **Accessibility** permission to move the mouse cursor. The bundle identifier is `com.hyperactive.app`.

On first launch (or when you click "Start"), macOS will prompt you to grant access:

**System Settings > Privacy & Security > Accessibility**

If the switch is already on and macOS still asks, the grant is for an older signature. Select Hyperactive, click the minus button to remove it, then add Hyperactive again. Turning the switch off and on is not enough. You can also clear the stale entry and add the app again:

```bash
tccutil reset Accessibility com.hyperactive.app
```

The menu item **Open Accessibility Settings…** opens that pane. After you grant access, Hyperactive notices within a couple of seconds. You do not need to quit it.

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
7. To run only during certain hours, open **Snooze** and choose **Edit Schedule…**. Each weekday has its own hours. **Weekdays Only** uses the outside mode all Saturday and Sunday, and keeps any weekend hours for when you turn that off. **Outside Hours** is **Off** (Hyperactive does nothing) or **Screen Only** (the display stays on, the pointer stays still)
8. With Snooze on, **Start** during a gap nudges until the next window or midnight, whichever comes first. **Stop** during a window stays idle until that window ends. The status line names the time

Snooze does not change **Keep Awake with Lid Closed**. While that is on, the Mac does not sleep, including outside active hours.

## Menu

```
Start / Stop              ⌘S
─────────────────────────────
Nudging until 2:00 PM — 12 nudges (last: 2:34 PM)
─────────────────────────────
Snooze ▸
  Turn Snooze Off
  Outside Hours: Off            ✓
  Outside Hours: Screen Only
  Weekdays Only
  Edit Schedule…
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
