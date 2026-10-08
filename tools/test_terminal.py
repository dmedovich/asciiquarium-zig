"""Exercise the real executable in a PTY, including terminal restoration."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else 'zig-out/bin/asciiquarium-zig').resolve())
version = Path(__file__).resolve().parents[1].joinpath('VERSION').read_text().strip()
assert subprocess.check_output([binary, '--version'], text=True).strip() == f'asciiquarium-zig {version}'
assert 'Usage:' in subprocess.check_output([binary, '--help'], text=True)
assert subprocess.run([binary, '--invalid'], capture_output=True).returncode == 1
assert subprocess.run([binary], stdin=subprocess.DEVNULL, capture_output=True).returncode == 1

for ending in (b'q', b'\x03', signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    master, slave = pty.openpty()
    original = termios.tcgetattr(slave)
    output = bytearray()
    process = None

    def resize(rows, cols):
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))

    def drain(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if select.select([master], [], [], max(0, deadline - time.monotonic()))[0]:
                output.extend(os.read(master, 65536))

    try:
        resize(24, 80)
        process = subprocess.Popen([binary], stdin=slave, stdout=slave, stderr=slave)
        deadline = time.monotonic() + 10
        while b'\x1b[?25l' not in output and time.monotonic() < deadline:
            drain(0.1)
        assert b'\x1b[?25l' in output, output
        os.write(master, b'ppr')
        drain(0.4)
        for rows, cols in ((5, 10), (12, 20), (130, 350), (24, 80)):
            resize(rows, cols)
            drain(0.25)
        if isinstance(ending, bytes):
            os.write(master, ending)
        else:
            process.send_signal(ending)
        deadline = time.monotonic() + 5
        while process.poll() is None and time.monotonic() < deadline:
            drain(0.1)
        assert process.poll() is not None, 'process did not exit'
        drain(0.1)
        expected = 0 if isinstance(ending, bytes) else 128 + ending
        assert process.returncode == expected, (process.returncode, output[-1000:])
        assert termios.tcgetattr(slave) == original, 'terminal settings not restored'
        assert b'\x1b[?25h\x1b[?1049l' in output, 'cursor/alternate screen not restored'
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
print('CLI, controls, resize and signal cleanup: passed')
