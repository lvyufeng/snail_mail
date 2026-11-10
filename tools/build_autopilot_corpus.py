#!/usr/bin/env python3
"""Make compact, readable traces for the checked-in autopilot evidence."""

import argparse
import json
from pathlib import Path
from typing import Iterator, List, Optional


def read_records(path: Path) -> Iterator[dict]:
    decoder = json.JSONDecoder()
    text = path.read_text()
    pos = 0
    while pos < len(text):
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text):
            break
        item, end = decoder.raw_decode(text, pos)
        if not isinstance(item, dict):
            raise ValueError(f"expected a JSON object in {path} at offset {pos}")
        yield item
        pos = end


def compact_record(record: dict) -> Optional[dict]:
    if record.get("kind") == "finish":
        return {k: record[k] for k in (
            "kind", "frame", "elapsed", "distance", "meter", "parcels", "falls", "won", "phase"
        ) if k in record}
    if record.get("kind") == "fall":
        return {k: record[k] for k in ("kind", "frame", "row", "x") if k in record}
    if "falling" not in record:
        return None
    row = {k: record[k] for k in (
        "frame", "elapsed", "distance", "row", "x", "targetX", "lane", "clearRows",
        "hazards", "rewards", "falling", "fallTime", "fallOffset", "playerXAtFall",
        "playerRowAtFall", "falls", "speed", "meter", "parcels", "weapon", "invincible",
        "phase", "airborne", "noFall"
    ) if k in record}
    for key in ("plan", "cameraShakeX", "cameraShakeY", "cameraX", "cameraHalfWidth"):
        if key in record and record[key] not in (None, [], 0):
            row[key] = record[key]
    if record.get("events"):
        row["events"] = [
            {k: event[k] for k in ("kind", "frame", "row", "x", "meterBefore", "meterAfter", "hazards")
             if k in event}
            for event in record["events"]
            if event.get("kind") in ("fall", "damage")
        ]
    def nearby(row_index):
        for segment in record.get("nearby", []):
            if segment.get("row") != row_index or not segment.get("sprites"):
                continue
            result = {k: segment[k] for k in ("row", "airborne", "noFall", "wall") if k in segment}
            result["sprites"] = [
                {k: sprite[k] for k in ("kind", "offset", "width", "depth") if k in sprite}
                for sprite in segment["sprites"]
            ]
            return result
        return None
    row_index = record.get("row", -1)
    if row_index >= 0:
        seen = {}
        for offset in (-1, 0, 1, 2, 3):
            item = nearby(row_index + offset)
            if item is not None:
                seen[row_index + offset] = item
        if seen:
            row["nearby"] = list(seen.values())
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--camera", type=Path, help="same-frame engine projection records")
    args = parser.parse_args()
    rows = []
    clipped = False
    for item in read_records(args.source):
        compact = compact_record(item)
        if compact is None:
            continue
        rows.append(compact)
        if len(rows) > 100000:
            clipped = True
    # Large failures are represented at every tenth frame, with every event
    # kept; successful full runs stay complete.
    if clipped:
        rows = [row for row in rows if row.get("kind") or row.get("events")
                or row.get("frame", 0) % 10 == 0]
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    with args.destination.open("w") as output:
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    if args.camera:
        camera = args.camera.with_suffix(".copied.jsonl")
        camera.write_text(args.camera.read_text())
    print(f"{len(rows)} records -> {args.destination}" + (" (clipped)" if clipped else ""))


if __name__ == "__main__":
    main()
