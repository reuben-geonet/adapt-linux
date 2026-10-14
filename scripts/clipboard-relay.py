"""Materialize ADAPT keyboard copies/cuts on Wayland while the app is open."""

import base64
import signal
import subprocess
import sys


def stop(_signum, _frame):
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    child = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE)
    try:
        for frame in child.stdout:
            try:
                payload = base64.b64decode(frame.strip(), validate=True)
            except ValueError:
                continue
            # Each frame is an explicit ADAPT keyboard copy/cut. Always acquire
            # ownership, including repeated copies of identical text. Imported
            # native clipboard changes do not generate frames or feedback.
            subprocess.run(
                ["wl-copy", "--type", "text/plain;charset=utf-8"],
                input=payload,
                check=True,
            )
    finally:
        if child.poll() is None:
            child.terminate()
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


if __name__ == "__main__":
    main()
