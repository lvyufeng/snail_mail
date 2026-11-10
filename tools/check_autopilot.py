#!/usr/bin/env python3
"""Summarise and check a -autopilot-trace recording.

The recording is produced by the debug game and includes the lane, the snail's
position, nearby track objects, falls, meter, and camera shake. The checker
fails if a run enters a fall, which makes a hands-free regression visible even
when a screenshot happens to miss the moment.
"""

import argparse
import json
import statistics
from collections import Counter
from pathlib import Path


def read_trace(path):
    records = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    # Runs saved while the replay was full-size often strip each frame's copy
    # of the event list to keep the file small, leaving only the event records.
    states = [row for row in records if "falling" in row]
    events = [row for row in records if row.get("kind") in ("fall", "damage")]
    finishes = [row for row in records if row.get("kind") == "finish"]
    if not states:
        states = [row for row in records if "falling" not in row and "frame" in row]
    if events and (not states or "events" not in states[0]):
        by_frame = {}
        for event in events:
            by_frame.setdefault(event["frame"], []).append(event)
        for state in states:
            state["events"] = by_frame.get(state["frame"], [])
    return states, finishes


def linear_fit(xs, ys):
    """Fit a camera-to-engine axis without assuming the screenshot delay."""
    count = len(xs)
    if count < 2:
        return None
    mean_x = sum(xs) / count
    mean_y = sum(ys) / count
    variance = sum((x - mean_x) ** 2 for x in xs)
    if variance < 1e-10:
        return None
    gain = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / variance
    # Signed engine motion must share the sign of signed camera motion.
    gain = max(0.1, gain)
    return gain, mean_y - gain * mean_x


def read_json_stream(path):
    """Read both line-delimited and adjacent JSON objects."""
    if not path or not path.exists():
        return []
    text = path.read_text()
    decoder = json.JSONDecoder()
    records = []
    pos = 0
    while pos < len(text):
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text):
            break
        item, pos = decoder.raw_decode(text, pos)
        if isinstance(item, dict):
            records.append(item)
    return records

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--max-falls", type=int, default=0)
    parser.add_argument("--vision", type=Path,
                        help="match autopilot-trace camera frames with vision readings")
    parser.add_argument("--camera-trace", type=Path,
                        help="engine pixels captured with the same animation frames")
    parser.add_argument("--tolerance", type=float, default=0.08,
                        help="maximum camera position error as a fraction of width")
    parser.add_argument("--max-incidents", type=int, default=20,
                        help="most recent incidents to print; 0 prints all")
    args = parser.parse_args()
    rows, finishes = read_trace(args.trace)
    if not rows:
        raise SystemExit("autopilot trace is empty")
    last = rows[-1] if rows else finishes[-1]
    hazards = Counter(kind for row in rows for kind in row.get("plan", []))
    first_fall = next((row["frame"] for row in rows if row.get("falling")), None)
    last_falls = finishes[-1].get("falls", last.get("falls", 0)) if finishes else last.get("falls", 0)
    print(f"frames={len(rows)} elapsed={last['elapsed']:.2f}s "
          f"distance={last['distance']:.0f} falls={last_falls} "
          f"meter={last['meter']} phase={last['phase']}")
    print("hazards=" + ", ".join(f"{k}:{v}" for k, v in sorted(hazards.items())))
    if finishes:
        print(f"finishes={len(finishes)}")
    if first_fall is not None:
        print(f"first fall on frame {first_fall}")
    incidents = []
    seen = set()
    for row in rows:
        for event in row.get("events", []):
            key = (event.get("kind"), event.get("frame"), event.get("row"))
            if key in seen:
                continue
            seen.add(key)
            if event.get("kind") in ("fall", "damageHazard"):
                event["frame"] = row["frame"]
                incidents.append(event)
    incidents = incidents[-args.max_incidents:] if args.max_incidents else incidents
    for incident in incidents:
        if incident["kind"] == "fall":
            print(f"incident frame={incident['frame']} fall row={incident['row']} "
                  f"x={incident['x']:.2f}")
        else:
            objects = incident.get("hazards", [])
            objects = [item.get("kind", str(item)) if isinstance(item, dict) else item
                       for item in objects]
            print(f"incident frame={incident['frame']} damage row={incident['row']} "
                  f"objects={','.join(objects) or 'nearby piece'}")
    latest_finish = finishes[-1:] if finishes else []
    for finish in latest_finish:
        print(f"finish frame={finish['frame']} won={finish['won']} "
              f"elapsed={finish['elapsed']:.2f}s meter={finish['meter']} "
              f"parcels={finish['parcels']} falls={finish['falls']}")
    falls = latest_finish[0].get("falls", last["falls"]) if latest_finish else last["falls"]
    if falls > args.max_falls:
        raise SystemExit(f"autopilot exceeded {args.max_falls} fall(s)")
    if args.vision:
        readings = [json.loads(line) for line in args.vision.read_text().splitlines()
                    if line.strip()]
        camera = {}
        for row in rows:
            camera[f"shot-{row['frame']:05d}.png"] = row
        for item in read_json_stream(args.camera_trace):
            if "frame" in item:
                camera[f"shot-{item['frame']:05d}.png"] = item
        engine_pixels = {}
        if args.camera_trace and args.camera_trace.exists():
            for item in read_json_stream(args.camera_trace):
                if all(key in item for key in ("roadCentrePx", "halfWidthPx", "snailPx")):
                    engine_pixels[item["frame"]] = item
        errors = []
        samples = []
        for reading in readings:
            visual = reading.get("snail")
            screen = reading.get("screen_frame")
            if screen:
                match = screen.split("-")
                reading["frame"] = f"shot-{int(match[-1]):05d}.png"
            row = camera.get(reading.get("frame"))
            if not row or not visual or "x" not in visual:
                continue
            # The engine already projects the visual road's centre and width.
            # This comparison calibrates the camera pixels; it does not infer
            # width from a possibly clipped row of the screenshot.
            frame_number = int(reading["frame"][5:-4])
            geometry = engine_pixels.get(frame_number, {})
            if not geometry:
                continue
            span = geometry["halfWidthPx"]
            centre = geometry["roadCentrePx"]
            fraction = span / 240.0
            model_x = geometry["engineX"] if "engineX" in geometry else row["x"]
            samples.append({"frame": frame_number, "engineX": model_x,
                            "cameraX": visual["x"], "centre": centre / 240.0,
                            "fraction": fraction, "snailPx": visual["x"] * 240,
                            "projectedSnail": geometry.get("snailPx"),
                            "roadEdge": reading.get("roadEdge")})
        for sample in samples:
            # Turbo stays centred at 120 px. Road centre and half-width are the
            # engine's projection for this same frame, so the viewport pixel
            # displacement converts directly to model offset.
            sample["cameraX"] = (sample["snailPx"] - sample["centre"] * 240) / (sample["fraction"] * 240)
            sample["error"] = abs(sample["cameraX"] - sample["engineX"])
        errors = [sample["error"] for sample in samples]
        if not samples:
            raise SystemExit("no captured frames match the trace")
        median = statistics.median(errors)
        near = sum(error <= args.tolerance for error in errors)
        print(f"vision={len(samples)}/{len(readings)} matched engine_frames={len(engine_pixels)} "
              f"median_error={median:.3f} "
              f"within_{args.tolerance:.2f}={near}/{len(samples)}")
        for sample in samples:
            print(f"vision frame={sample['frame']} engine_x={sample['engineX']:.3f} "
                  f"camera_x={sample['cameraX']:.3f} error={sample['error']:.3f}")
        if median > args.tolerance:
            raise SystemExit("camera reading does not agree with the engine")


if __name__ == "__main__":
    main()
