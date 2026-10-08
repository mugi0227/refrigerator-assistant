"""Capture only Fridge's native iPhone log over an already paired USB link."""
from __future__ import annotations

import argparse
import asyncio
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

from pymobiledevice3 import usbmux


async def select_device() -> str:
    devices = [d for d in await asyncio.wait_for(usbmux.list_devices(), 8) if d.is_usb]
    if len(devices) != 1:
        raise RuntimeError("Connect and unlock exactly one USB iPhone first.")
    return devices[0].serial


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=180)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.seconds <= 600:
        parser.error("--seconds must be between 1 and 600")
    try:
        device = asyncio.run(select_device())
        env = {**os.environ, "PYTHONIOENCODING": "utf-8", "NO_COLOR": "1"}
        command = [sys.executable, "-m", "pymobiledevice3"]
        info = subprocess.run(command + ["lockdown", "info", "--udid", device],
                              capture_output=True, text=True, encoding="utf-8", timeout=15,
                              check=True, env=env)
        values = json.loads(info.stdout)
        metadata = {k: values.get(k) for k in ("ProductType", "ProductVersion", "BuildVersion")}
        print(json.dumps(metadata, ensure_ascii=True), flush=True)
        if args.check_only:
            return 0
        out = Path(__file__).resolve().parent.parent / "local"
        out.mkdir(exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        path = out / f"fridge-iphone-{stamp}.jsonl"
        path.with_suffix(".metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        print(f"Recording Fridge for {args.seconds} seconds. Open Fridge and start the saved model now.", flush=True)
        print(f"Log: {path}", flush=True)
        with path.open("w", encoding="utf-8") as log:
            try:
                result = subprocess.run(command + ["syslog", "live", "--udid", device,
                    "--process-name", "Fridge", "--format", "json"],
                    stdout=log, stderr=subprocess.PIPE, text=True, encoding="utf-8",
                    timeout=args.seconds, env=env)
            except subprocess.TimeoutExpired:
                pass  # subprocess.run stops its child before returning.
            else:
                if result.returncode:
                    print(result.stderr[-2000:], file=sys.stderr)
                    return result.returncode
        print(f"Saved {path.stat().st_size} bytes. No other apps' log entries were saved.", flush=True)
        return 0
    except (RuntimeError, subprocess.SubprocessError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
