#!/usr/bin/env python3
"""Extract ImageGen poses unchanged, then encode an explicitly stepped animatic.

No new poses, deformation, interpolation, retiming within a pose, or camera
motion are synthesized. Cells use round(i * width / 4), round(j * height / 2).
Odd-size cells lose at most one right/bottom pixel to equalize frame dimensions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


TIMINGS = {
    "waddle": [0.15] * 8,
    "jump": [0.20, 0.12, 0.12, 0.18, 0.18, 0.12, 0.16, 0.50],
    "slide": [0.15] * 8,
}


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assemble(source: Path, output: Path, action: str) -> dict:
    source, output = source.resolve(), output.resolve()
    for command in ("magick", "ffmpeg", "ffprobe"):
        if not shutil.which(command):
            raise SystemExit(f"Missing required command: {command}")
    if not source.is_file():
        raise SystemExit(f"Missing sprite sheet: {source}")
    output.mkdir(parents=True, exist_ok=True)
    dimensions = run("magick", "identify", "-ping", "-format", "%w %h", str(source)).split()
    if len(dimensions) != 2:
        raise SystemExit("Expected one still image containing a 4-column × 2-row sheet")
    width, height = map(int, dimensions)
    x = [round(i * width / 4) for i in range(5)]
    y = [round(i * height / 2) for i in range(3)]
    frame_width = min(x[i + 1] - x[i] for i in range(4))
    frame_height = min(y[i + 1] - y[i] for i in range(2))
    if frame_width < 2 or frame_height < 2:
        raise SystemExit("Sprite sheet dimensions are too small")

    frames = []
    records = []
    durations = TIMINGS[action]
    for index in range(8):
        column, row = index % 4, index // 4
        bounds = [x[column], y[row], x[column + 1], y[row + 1]]
        right_trim = bounds[2] - bounds[0] - frame_width
        bottom_trim = bounds[3] - bounds[1] - frame_height
        if right_trim not in (0, 1) or bottom_trim not in (0, 1):
            raise AssertionError("Unexpected cell-size discrepancy")
        frame = output / f"{action}-frame-{index + 1:02d}.png"
        crop = f"{frame_width}x{frame_height}+{bounds[0]}+{bounds[1]}"
        run("magick", str(source), "-crop", crop,
            "+repage", str(frame))
        expected_pixels = run("magick", str(source), "-crop", crop, "+repage", "-format", "%#", "info:")
        actual_pixels = run("magick", str(frame), "-format", "%#", "info:")
        if expected_pixels != actual_pixels:
            raise AssertionError(f"Pixel extraction mismatch: {frame.name}")
        frames.append(frame)
        records.append({"frame": index + 1, "file": frame.name,
                        "sheet_bounds_xyxy": bounds,
                        "trim_right_bottom_px": [right_trim, bottom_trim],
                        "duration_seconds": durations[index], "sha256": sha256(frame),
                        "source_crop_pixel_signature": expected_pixels,
                        "lossless_pixel_match": True})

    gif = output / f"{action}.gif"
    gif_args = ["magick", "-dispose", "none"]
    for frame, duration in zip(frames, durations):
        gif_args.extend(["-delay", str(round(duration * 100)), str(frame)])
    gif_args.extend(["-loop", "0", "-layers", "Optimize", str(gif)])
    run(*gif_args)

    # A centisecond timebase preserves GIF-equivalent hold times exactly.
    # The fps filter duplicates identical pixels during each hold; it never
    # interpolates a pose. The repeated final still supplies the end timestamp.
    concat = output / f"{action}-timing.ffconcat"
    concat.write_text("ffconcat version 1.0\n" + "".join(
        f"file '{frame.name}'\noption framerate 100\nduration {duration:.2f}\n"
        for frame, duration in zip(frames, durations)) + f"file '{frames[-1].name}'\noption framerate 100\n")
    mp4 = output / f"{action}.mp4"
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
        "-i", str(concat), "-an", "-vf", "fps=100,pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:color=black",
        "-fps_mode", "cfr", "-t", f"{sum(durations):.2f}", "-c:v", "libx264",
        "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4))
    video = json.loads(run("ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=codec_name,width,height,nb_frames:format=duration",
                          "-of", "json", str(mp4)))
    gif_frames = [list(map(int, line.split())) for line in run(
        "magick", "identify", "-format", "%W %H %T\n", str(gif)).splitlines()]
    if gif_frames != [[frame_width, frame_height, round(duration * 100)] for duration in durations]:
        raise AssertionError(f"GIF dimensions, frame count or timing mismatch: {gif_frames}")
    expected_duration = round(sum(durations), 2)
    if abs(float(video["format"]["duration"]) - expected_duration) > 0.005:
        raise AssertionError(f"MP4 duration mismatch: {video}")
    if int(video["streams"][0]["nb_frames"]) != round(expected_duration * 100):
        raise AssertionError(f"MP4 hold-frame count mismatch: {video}")
    receipt = {
        "schema": 1, "action": action,
        "description": "Eight generated still poses played as a stepped reference animatic; not a game capture or finished animation.",
        "source_file": source.name, "source_sha256": sha256(source),
        "source_dimensions": [width, height], "grid": [4, 2],
        "frame_dimensions": [frame_width, frame_height],
        "extraction": "Original pixels; nearest rounded grid boundaries; at most one right/bottom pixel trimmed per cell; no resize or retouch.",
        "source_pose_count": 8, "timing_seconds": durations, "sequence_seconds": round(sum(durations), 2),
        "loop_transition": "Cyclic authored poses" if action in ("waddle", "slide") else "Final-pose hold, then deliberate hard cut to first pose; no generated recovery or interpolation",
        "frames": records,
        "verification": {"lossless_source_crops": 8, "gif_frames": 8, "timings_verified": True},
        "gif": {"file": gif.name, "sha256": sha256(gif), "canvas_width_height_delay_centiseconds": gif_frames,
                "encoding": "GIF palette encoding; infinite loop"},
        "mp4": {"file": mp4.name, "sha256": sha256(mp4), "probe": video,
                "encoding": "H.264 yuv420p at 100 frames/sec for exact centisecond holds; duplicate stills only; at most one right/bottom padding pixel for even dimensions; no interpolation"},
    }
    (output / f"{action}-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--action", choices=TIMINGS, required=True)
    args = parser.parse_args()
    result = assemble(args.source, args.output, args.action)
    print(json.dumps({key: result[key] for key in
                      ("action", "source_dimensions", "frame_dimensions", "sequence_seconds", "loop_transition")}, indent=2))
