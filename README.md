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
- **Invisible** — no Dock icon, no Cmd-Tab entry
- **Lightweight** — native Swift, ~3 MB, negligible CPU

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (the app will prompt you)

## Install

### From Release

1. Download `Hyperactive.dmg` from Releases
2. Drag `Hyperactive.app` to `/Applications`
3. Launch — if you see a Gatekeeper warning, right-click > Open
4. Grant Accessibility access when prompted

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

## Permissions

Hyperactive needs **Accessibility** permission to move the mouse cursor.

On first launch (or when you click "Start"), macOS will prompt you to grant access:

**System Settings > Privacy & Security > Accessibility > Hyperactive** — toggle ON.

If you miss the prompt, click **"Grant Accessibility Access..."** in the app's menu.

## Usage

1. Click the cursor icon in the menu bar
2. Click **Start** — the icon changes to show motion lines
3. The mouse will nudge every 5 minutes (default)
4. To change the interval: **Interval >** submenu
5. Click **Stop** to deactivate

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
