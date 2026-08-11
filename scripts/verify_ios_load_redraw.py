#!/usr/bin/env python3
"""Verify that the iOS quick-load action redraws without a lifecycle event."""

import argparse
import re
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageOps, ImageStat


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, **kwargs)


def lldb(pid: int, commands: list[str]) -> str:
    invocation = ["xcrun", "lldb", "-b", "-p", str(pid)]
    for command in commands:
        invocation.extend(["-o", command])
    invocation.extend(["-o", "detach", "-o", "quit"])
    result = subprocess.run(invocation, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def launch(simulator: str, bundle_id: str) -> int:
    subprocess.run(
        ["xcrun", "simctl", "terminate", simulator, bundle_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    result = run(
        ["xcrun", "simctl", "launch", simulator, bundle_id],
        capture_output=True,
    )
    match = re.search(r":\s*(\d+)\s*$", result.stdout)
    if not match:
        raise RuntimeError(f"could not parse app pid from: {result.stdout!r}")
    return int(match.group(1))


def capture(simulator: str, destination: Path) -> None:
    run(
        [
            "xcrun",
            "simctl",
            "io",
            simulator,
            "screenshot",
            "--type=png",
            str(destination),
        ],
        stdout=subprocess.DEVNULL,
    )


def magenta_ratio(path: Path) -> float:
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    if image.height > image.width:
        image = image.transpose(Image.Transpose.ROTATE_90)
    left = image.width // 4
    right = image.width - left
    pixels = image.crop((left, 0, right, image.height)).get_flattened_data()
    magenta = sum(red > 220 and green < 35 and blue > 220 for red, green, blue in pixels)
    return magenta / ((right - left) * image.height)


def frame_difference(first_path: Path, second_path: Path) -> float:
    first = ImageOps.exif_transpose(Image.open(first_path)).convert("RGB")
    second = ImageOps.exif_transpose(Image.open(second_path)).convert("RGB")
    if first.height > first.width:
        first = first.transpose(Image.Transpose.ROTATE_90)
    if second.height > second.width:
        second = second.transpose(Image.Transpose.ROTATE_90)
    if first.size != second.size:
        return 255.0
    left = first.width // 4
    right = first.width - left
    box = (left, 0, right, first.height)
    difference = ImageChops.difference(first.crop(box), second.crop(box))
    return sum(ImageStat.Stat(difference).mean) / 3.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--bundle-id", default="com.local.smw.ios")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    pid = launch(args.simulator, args.bundle_id)
    time.sleep(3.0)

    lldb(
        pid,
        [
            "expr g_paused = 1",
            "expr g_ram[0x1ff00] = 0x5a",
            "expr -l c -- RtlSaveLoad(1, 0)",
        ],
    )

    with tempfile.TemporaryDirectory(prefix="smw-load-redraw-") as temp_dir:
        saved_frame = Path(temp_dir) / "saved-frame.png"
        capture(args.simulator, saved_frame)

        lldb(
            pid,
            [
                "expr g_ram[0x1ff00] = 0xa5",
                "expr -l c++ -- unsigned char *$pixels = 0; int $pitch = 0; SdlRenderer_BeginDraw(256, 224, &$pixels, &$pitch)",
                "expr -l c++ -- for (int $y = 0; $y < 224; ++$y) for (int $x = 0; $x < 256; ++$x) ((unsigned int *)($pixels + $y * $pitch))[$x] = 0xffff00ff",
                "expr -l c++ -- SdlRenderer_EndDraw()",
                "expr -l objc++ -- (void)[(SMWTouchOverlay *)gOverlay openSettings]",
                "expr -l objc++ -- id $settings = (id)[(id)gOverlay valueForKey:@\"_settings\"]",
                "expr -l objc++ -- (void)[$settings loadState]",
                "expr -l objc++ -- (void)[$settings confirmPendingAction]",
            ],
        )
        time.sleep(1.0)

        state = lldb(
            pid,
            [
                "p/x g_ram[0x1ff00]",
                "p/x g_paused",
                "p gPendingActions",
            ],
        )
        try:
            print(f"paused_after_load={'yes' if '(uint8) 0x01' in state else 'no'}")
            if "0x5a" not in state:
                print("FAIL: quick-load did not restore the saved emulator state")
                return 1

            screenshot = args.output or Path(temp_dir) / "after-load.png"
            capture(args.simulator, screenshot)
            ratio = magenta_ratio(screenshot)
            difference = frame_difference(saved_frame, screenshot)
        finally:
            lldb(pid, ["expr g_paused = 0"])

    print(f"stale_magenta={ratio:.2%} saved_frame_difference={difference:.2f}/255")
    if ratio > 0.05 or difference > 2.0:
        print("FAIL: quick-load restored state but left the previous frame on screen")
        return 1
    print("PASS: quick-load restored state and presented the loaded frame immediately")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
