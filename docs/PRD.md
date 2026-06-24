# Hyperactive — Product Requirements Document

## Vision

Hyperactive is a lightweight macOS menu bar utility that helps keep a Mac awake by periodically nudging the mouse cursor. It is inspired by utilities like Caffeine, but instead of only preventing sleep through system assertions, it keeps the system active through tiny cursor movements.

It replaces the command-line `keep_active.py` script with a native, one-click experience.

## Problem

Sometimes a Mac may dim, lock, sleep, or otherwise appear inactive during legitimate periods where the user is still engaged but not actively using the keyboard or mouse: reading documents, monitoring dashboards, watching a long-running process, downloads, renders, or thinking through a task.

Traditional keep-awake tools are useful, but some scenarios benefit from an explicit, minimal cursor movement that keeps the system active without interfering with normal usage.

## Target User

macOS users who want a lightweight, visible, and configurable way to keep their system active during legitimate hands-off periods.

## User Stories

1. **As a user**, I want to toggle cursor nudging on/off from the menu bar with a single click, so I don't need to open Terminal.
2. **As a user**, I want to see whether cursor nudging is enabled at a glance via the menu bar icon.
3. **As a user**, I want to adjust the nudge interval, so I can balance between reliability and system resources.
4. **As a user**, I want the app to launch automatically at login, so I don't forget to start it when needed.
5. **As a user**, I want the app to be invisible in the Dock and Cmd-Tab, so it stays out of the way.
6. **As a user**, I want to see how many nudges have occurred and when the last one happened.

## Features

### Core (v1.0)
- Menu bar icon with active/inactive state (SF Symbols)
- Start/Stop toggle
- Mouse nudge: move cursor ±2-4px and back every N minutes
- Configurable interval: 1, 2, 5, 10, 15, 30 minutes
- Activity display: nudge count and last nudge time
- Accessibility permission detection and guided setup
- Launch at Login toggle
- No Dock icon (LSUIElement)
- Resume after system wake

### Non-Goals (v1.0)
- Windows/Linux support
- Custom nudge distance
- Scheduling (active hours)
- Keystroke simulation
- Auto-update mechanism

## Technical Requirements

- **Platform**: macOS 14.0+ (Sonoma)
- **Framework**: SwiftUI with MenuBarExtra
- **APIs**: CGEvent (mouse), AXIsProcessTrusted (permissions), SMAppService (login item)
- **Sandbox**: Disabled (CGEventPost requires unsandboxed execution)
- **Size**: < 5 MB app bundle
- **CPU**: Negligible (timer fires once every few minutes)

## Success Metrics

- App builds and runs without errors on macOS 14+
- Mouse nudge reliably performs tiny cursor movement and returns to original position
- Menu bar icon updates correctly on state change
- Timer survives system sleep/wake cycles
- App does not appear in Dock or Cmd-Tab

## Risks

| Risk | Mitigation |
|------|------------|
| macOS tightens CGEvent restrictions | Monitor release notes; fall back to Accessibility API |
| Cursor movement becomes noticeable in edge cases | Keep offsets tiny and immediately move back |
| User forgets to grant Accessibility | Clear prompts and menu item to open System Settings |
