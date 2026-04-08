#!/usr/bin/env python3
"""
Launch a terminal UI example inside a PTY, send mouse input, and fail if the
process exits unexpectedly or crashes.

This keeps crash-class regression coverage out of the current process so CI can
detect stack overflows without taking down the test runner itself.
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
from dataclasses import dataclass


@dataclass(frozen=True)
class EventSequence:
    name: str
    payload: bytes


EVENT_SEQUENCES = {
    "click": EventSequence(
        name="click at (5,5)",
        payload=b"\x1b[<0;6;6M\x1b[<0;6;6m",
    ),
    "scroll": EventSequence(
        name="scroll-down at (5,5)",
        payload=b"\x1b[<65;6;6M",
    ),
}


def set_winsize(fd: int, rows: int, cols: int) -> None:
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def drain_output(fd: int, timeout: float = 0.1) -> None:
    while select.select([fd], [], [], timeout)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            break


def child_status(pid: int) -> tuple[int, int]:
    try:
        return os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return (pid, 0)


def terminate_child(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return

    deadline = time.time() + 1.0
    while time.time() < deadline:
        wpid, _ = child_status(pid)
        if wpid != 0:
            return
        time.sleep(0.05)

    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        return
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        return


def run_sequence(
    binary: str,
    sequence: EventSequence,
    count: int,
    rows: int,
    cols: int,
    startup_delay: float,
    settle_delay: float,
    event_interval: float,
) -> int:
    pid, fd = pty.fork()

    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execv(binary, [binary])
        sys.exit(127)

    try:
        set_winsize(fd, rows, cols)
        time.sleep(startup_delay)
        drain_output(fd)

        print(f"Running {sequence.name} against {binary}")
        for index in range(count):
            print(f"  Event {index + 1}/{count}: {sequence.payload!r}")
            try:
                os.write(fd, sequence.payload)
            except OSError:
                break
            if event_interval > 0:
                time.sleep(event_interval)

        time.sleep(settle_delay)
        wpid, status = child_status(pid)

        if wpid == 0:
            print("  PASS: process remained alive after input")
            return 0

        if os.WIFSIGNALED(status):
            signum = os.WTERMSIG(status)
            if signum in signal.Signals._value2member_map_:
                name = signal.Signals(signum).name
            else:
                name = str(signum)
            print(f"  CRASH: signal {name} ({signum})", file=sys.stderr)
            return 1

        exit_code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
        print(f"  EARLY EXIT: code {exit_code}", file=sys.stderr)
        return 1
    finally:
        terminate_child(pid)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, help="Path to the built executable")
    parser.add_argument(
        "--event",
        action="append",
        choices=sorted(EVENT_SEQUENCES.keys()),
        help="Input event sequence to run. Defaults to click + scroll.",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="Number of event sequences to send",
    )
    parser.add_argument("--rows", type=int, default=50, help="PTY row count")
    parser.add_argument("--cols", type=int, default=120, help="PTY column count")
    parser.add_argument(
        "--startup-delay",
        type=float,
        default=1.0,
        help="Seconds to wait before sending input",
    )
    parser.add_argument(
        "--settle-delay",
        type=float,
        default=1.0,
        help="Seconds to wait after sending input",
    )
    parser.add_argument(
        "--event-interval",
        type=float,
        default=0.0,
        help="Delay between events",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    binary = os.path.abspath(args.binary)
    if not os.path.isfile(binary):
        print(f"Binary not found: {binary}", file=sys.stderr)
        return 2

    events = args.event if args.event else ["click", "scroll"]
    for event_name in events:
        result = run_sequence(
            binary=binary,
            sequence=EVENT_SEQUENCES[event_name],
            count=args.count,
            rows=args.rows,
            cols=args.cols,
            startup_delay=args.startup_delay,
            settle_delay=args.settle_delay,
            event_interval=args.event_interval,
        )
        if result != 0:
            return result

    return 0


if __name__ == "__main__":
    sys.exit(main())
