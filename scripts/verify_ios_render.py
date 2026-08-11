#!/usr/bin/env python3
"""Detect distorted or non-integer scaling of the 256x224 framebuffer."""

import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageOps


FRAMEBUFFER_WIDTH = 256
FRAMEBUFFER_HEIGHT = 224
VIEWPORT_EDGE_TOLERANCE = 2


def is_game_pixel(pixel: tuple[int, int, int]) -> bool:
    return max(pixel) > 40 and max(pixel) - min(pixel) > 24


def capture(simulator_id: str, destination: Path) -> None:
    subprocess.run(
        [
            "xcrun",
            "simctl",
            "io",
            simulator_id,
            "screenshot",
            "--type=png",
            str(destination),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def longest_true_run(dense: list[bool]) -> tuple[int, int]:
    dense = dense.copy()
    gap_start = 0
    while gap_start < len(dense):
        if dense[gap_start]:
            gap_start += 1
            continue
        gap_end = gap_start
        while gap_end < len(dense) and not dense[gap_end]:
            gap_end += 1
        if gap_start > 0 and gap_end < len(dense) and gap_end - gap_start <= 8:
            dense[gap_start:gap_end] = [True] * (gap_end - gap_start)
        gap_start = gap_end

    best_start = best_end = run_start = 0
    in_run = False
    for position, is_dense in enumerate(dense + [False]):
        if is_dense and not in_run:
            run_start = position
            in_run = True
        elif not is_dense and in_run:
            if position - run_start > best_end - best_start:
                best_start, best_end = run_start, position
            in_run = False
    return best_start, best_end


def vertical_viewport(image: Image.Image) -> tuple[int, int]:
    width, height = image.size
    left = width // 4
    right = width - left
    dense = []
    for y in range(height):
        lit = sum(is_game_pixel(image.getpixel((x, y))) for x in range(left, right))
        dense.append(lit / (right - left) > 0.03)
    return longest_true_run(dense)


def horizontal_viewport(image: Image.Image, top: int, bottom: int) -> tuple[int, int]:
    dense = []
    viewport_height = bottom - top
    for x in range(image.width):
        lit = sum(is_game_pixel(image.getpixel((x, y))) for y in range(top, bottom))
        dense.append(lit / viewport_height > 0.03)
    return longest_true_run(dense)


def refine_vertical_viewport(image: Image.Image, left: int, right: int) -> tuple[int, int]:
    width = right - left
    sample_columns = list(range(left, left + width // 3)) + list(
        range(right - width // 3, right)
    )
    dense = []
    for y in range(image.height):
        lit = sum(max(image.getpixel((x, y))) > 24 for x in sample_columns)
        dense.append(lit / len(sample_columns) > 0.03)
    return longest_true_run(dense)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path)
    parser.add_argument("--simulator")
    args = parser.parse_args()

    if args.image is None and args.simulator is None:
        parser.error("pass --image or --simulator")

    with tempfile.TemporaryDirectory(prefix="smw-render-check-") as temp_dir:
        image_path = args.image or Path(temp_dir) / "screen.png"
        if args.image is None:
            capture(args.simulator, image_path)

        image = ImageOps.exif_transpose(Image.open(image_path)).convert("RGB")
        if image.height > image.width:
            image = image.transpose(Image.Transpose.ROTATE_90)
        top, bottom = vertical_viewport(image)
        left, right = horizontal_viewport(image, top, bottom)
        top, bottom = refine_vertical_viewport(image, left, right)
        viewport_width = right - left
        viewport_height = bottom - top
        x_scale = viewport_width / FRAMEBUFFER_WIDTH
        y_scale = viewport_height / FRAMEBUFFER_HEIGHT
        distortion = abs(x_scale / y_scale - 1.0)
        integer_scale = round((x_scale + y_scale) / 2.0)
        width_error = abs(viewport_width - FRAMEBUFFER_WIDTH * integer_scale)
        height_error = abs(viewport_height - FRAMEBUFFER_HEIGHT * integer_scale)

        print(
            f"viewport={viewport_width}x{viewport_height}@({left},{top}) "
            f"scale={x_scale:.4f}x{y_scale:.4f} distortion={distortion:.2%}"
        )
        if distortion > 0.02:
            print("FAIL: framebuffer pixels are visibly non-square")
            return 1
        if (
            integer_scale < 1
            or width_error > VIEWPORT_EDGE_TOLERANCE
            or height_error > VIEWPORT_EDGE_TOLERANCE
        ):
            print(
                "FAIL: framebuffer uses a fractional physical-pixel scale "
                f"(nearest={integer_scale}x, edge error={width_error}x{height_error}px)"
            )
            return 1
        print(f"PASS: framebuffer uses a consistent {integer_scale}x physical-pixel grid")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
