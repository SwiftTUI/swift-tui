#!/usr/bin/env python3
"""
Reproduce scroll-diagnostic stack overflow crash by launching the
release binary in a PTY and sending SGR mouse events.

The crash is release-only: optimized builds inline view resolution
functions, creating stack frames large enough to overflow the Swift
concurrency cooperative thread stack (~512 KB).

Usage:
    # Build release first
    swift build -c release

    # Reproduce with click (default)
    python3 repro_crash.py

    # Reproduce with scroll
    python3 repro_crash.py --scroll

Exit codes:
    0 = crash reproduced (child died with a signal)
    1 = no crash (child stayed alive or exited cleanly)
"""
from __future__ import annotations

import argparse
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time


def set_winsize(fd: int, rows: int, cols: int) -> None:
    """Set the terminal window size on the PTY."""
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def drain_output(fd: int, timeout: float = 0.1) -> None:
    """Drain pending output from the PTY without blocking."""
    while select.select([fd], [], [], timeout)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            break


def run_with_event(
    binary: str,
    event_bytes: bytes,
    event_label: str,
    startup_delay: float,
    crash_delay: float,
    count: int,
    rows: int,
    cols: int,
    event_interval: float,
) -> bool:
    """Launch binary in a PTY, send event_bytes, return True if it crashed."""
    pid, fd = pty.fork()

    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execv(binary, [binary])
        sys.exit(127)

    try:
        set_winsize(fd, rows, cols)
        time.sleep(startup_delay)
        drain_output(fd)

        for i in range(0, count):
            print(f"  Sending {event_label}...{event_bytes}")
            try:
                os.write(fd, event_bytes)
            except OSError:
                # Child likely crashed — PTY closed
                time.sleep(0.2)
                break
            if event_interval > 0:
                time.sleep(event_interval)

        time.sleep(crash_delay)

        wpid, status = os.waitpid(pid, os.WNOHANG)

        if wpid != 0 and os.WIFSIGNALED(status):
            sig = os.WTERMSIG(status)
            sig_name = (
                signal.Signals(sig).name
                if sig in signal.Signals._value2member_map_
                else str(sig)
            )
            print(f"  CRASH: signal {sig_name} ({sig})")
            return True

        if wpid != 0:
            code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
            print(f"  Exited with code {code} (no crash)")
            return False

        print("  No crash (still running)")
        os.kill(pid, signal.SIGTERM)
        time.sleep(0.3)
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        return False

    except Exception as e:
        print(f"  Error: {e}", file=sys.stderr)
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except (OSError, ChildProcessError):
            pass
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scroll", action="store_true", help="Send scroll instead of click"
    )
    parser.add_argument(
        "--binary",
        default=".build/release/scroll-diagnostic",
        help="Path to binary (default: release build)",
    )
    parser.add_argument(
        "--startup-delay",
        type=float,
        default=1.5,
        help="Seconds to wait for app startup",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="Number of events to send",
    )
    parser.add_argument(
        "--event-interval",
        type=float,
        default=0.0,
        help="Seconds between events (0 = no delay, simulates rapid input)",
    )
    parser.add_argument(
        "--crash-delay",
        type=float,
        default=1.5,
        help="Seconds to wait for crash after input",
    )
    parser.add_argument(
        "--rows", type=int, default=50, help="PTY rows"
    )
    parser.add_argument(
        "--cols", type=int, default=120, help="PTY columns"
    )
    args = parser.parse_args()

    binary = os.path.abspath(args.binary)
    if not os.path.isfile(binary):
        print(f"Binary not found: {binary}", file=sys.stderr)
        print("Run: swift build -c release", file=sys.stderr)
        sys.exit(2)

    # SGR mouse format: ESC [ < button ; col ; row M(press) / m(release)
    # Coordinates are 1-indexed
    if args.scroll:
        event_bytes = b"\x1b[<65;6;6M"  # scroll down at (5,5)
        label = "scroll-down at (5,5)"
    else:
        event_bytes = b"\x1b[<0;6;6M\x1b[<0;6;6m"  # click at (5,5)
        label = "click at (5,5)"

    print(f"Testing {label} with {binary}...")
    crashed = run_with_event(
        binary,
        event_bytes,
        label,
        args.startup_delay,
        args.crash_delay,
        args.count,
        args.rows,
        args.cols,
        args.event_interval,
    )
    sys.exit(0 if crashed else 1)


if __name__ == "__main__":
    main()
