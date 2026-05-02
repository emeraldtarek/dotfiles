#!/usr/bin/env python3
"""Split full/*.md into batches under batches/sumbatch_NN.txt for parallel summarizer agents."""
from __future__ import annotations
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FULL = ROOT / "full"
OUT = ROOT / "batches"

BATCH_COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 10


def main() -> int:
    files = sorted(p.name for p in FULL.glob("*.md"))
    if not files:
        print("no files in full/", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    # Clear previous batches
    for old in OUT.glob("sumbatch_*.txt"):
        old.unlink()

    per = math.ceil(len(files) / BATCH_COUNT)
    for i in range(BATCH_COUNT):
        chunk = files[i * per : (i + 1) * per]
        if not chunk:
            continue
        path = OUT / f"sumbatch_{i:02d}.txt"
        path.write_text("\n".join(chunk) + "\n")
        print(f"{path.name}: {len(chunk)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
