#!/usr/bin/env python3
"""
Cursor nudger — helps keep macOS active by periodically moving the mouse.
Uses AppleScript via osascript (no Python dependencies needed).

Usage: python3 keep_active.py -t 5
Stop:  Ctrl+C
"""

import argparse
import time
import signal
import sys
import subprocess
import random


def nudge():
    """Move mouse a few pixels using AppleScript + coreutils."""
    # Get mouse position and move it using AppleScript
    dx = random.choice([-4, -3, -2, 2, 3, 4])
    dy = random.choice([-4, -3, -2, 2, 3, 4])

    script = f'''
    tell application "System Events"
        set pos to position of the mouse
        set curX to item 1 of pos
        set curY to item 2 of pos
        set newX to curX + {dx}
        set newY to curY + {dy}
    end tell

    do shell script "printf '%d %d' " & newX & " " & newY
    '''

    # Try approach 1: pure AppleScript mouse move via System Events
    move_script = f'''
    tell application "System Events"
        set pos to position of the mouse
        set curX to item 1 of pos
        set curY to item 2 of pos
    end tell

    tell application "System Events"
        key code 63
    end tell
    '''

    # Most reliable macOS approach: use applescript with mouse keys
    # Actually simplest: use the `mouse` movement via CGEvent in swift inline
    # But even simpler: use osascript to run a tiny swift snippet

    # Simplest reliable approach: use python mouse move via subprocess calling
    # osascript with cliclick, or use the Accessibility API via applescript

    # Let's use the simplest thing that works: osascript calling
    # JavaScript for Automation (JXA) which has mouse support

    jxa_script = f'''
    ObjC.import('CoreGraphics');
    var event = $.CGEventCreate(null);
    var point = $.CGEventGetLocation(event);
    var x = point.x + {dx};
    var y = point.y + {dy};
    var move = $.CGEventCreateMouseEvent(null, $.kCGEventMouseMoved, $.CGPointMake(x, y), $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, move);
    // move back
    ObjC.import('Cocoa');
    $.NSThread.sleepForTimeInterval(0.15);
    var back = $.CGEventCreateMouseEvent(null, $.kCGEventMouseMoved, point, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, back);
    '''

    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", jxa_script],
        capture_output=True, text=True, timeout=10
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())


def main():
    parser = argparse.ArgumentParser(
        description="Keep macOS active by moving the mouse periodically."
    )
    parser.add_argument(
        "-t", type=float, default=5, help="Interval in minutes (default: 5)"
    )
    args = parser.parse_args()

    interval = args.t * 60

    def handle_signal(sig, frame):
        print("\n\n✋ Stopped. The system may become inactive normally now.")
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    # Self-test
    print("🔍 Testing mouse control...")
    try:
        nudge()
        print("✅ Mouse move works!")
    except Exception as e:
        print(f"❌ Mouse move failed: {e}")
        print("\n   Make sure Terminal has Accessibility access:")
        print("   System Settings → Privacy & Security → Accessibility → Terminal ✅")
        sys.exit(1)

    print(f"🟢 Moving every {args.t} min — Ctrl+C to stop\n")

    count = 0
    while True:
        count += 1
        now = time.strftime("%H:%M:%S")
        try:
            nudge()
            print(f"  [{now}] nudge #{count} ✓")
        except Exception as e:
            print(f"  [{now}] nudge #{count} ✗ {e}")
        time.sleep(interval)


if __name__ == "__main__":
    main()
