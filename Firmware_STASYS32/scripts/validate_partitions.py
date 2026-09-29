#!/usr/bin/env python3
"""Validate a CSV partition table against an explicitly supplied flash size."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path


def size_bytes(value: str) -> int:
    value = value.strip().lower()
    units = {"k": 1024, "kb": 1024, "m": 1024 * 1024, "mb": 1024 * 1024}
    for suffix, multiplier in units.items():
        if value.endswith(suffix):
            return int(value[:-len(suffix)], 0) * multiplier
    return int(value, 0)


def validate(path: Path, flash_size: int) -> list[str]:
    errors: list[str] = []
    ranges: list[tuple[int, int, str]] = []
    with path.open(newline="", encoding="utf-8") as stream:
        for line_no, row in enumerate(csv.reader(stream), 1):
            if not row or row[0].strip().startswith("#"):
                continue
            row += [""] * (5 - len(row))
            name, _kind, _subtype, offset_text, size_text = [cell.strip() for cell in row[:5]]
            if not name or name.lower() == "name":
                continue
            try:
                offset = size_bytes(offset_text)
                size = size_bytes(size_text)
            except ValueError:
                errors.append(f"line {line_no}: invalid offset/size for {name}")
                continue
            if offset < 0:
                errors.append(f"line {line_no}: negative offset for {name}")
                continue
            if size <= 0:
                errors.append(f"line {line_no}: non-positive size for {name}")
                continue
            end = offset + size
            if end > flash_size:
                errors.append(f"line {line_no}: {name} ends at 0x{end:x}, beyond flash 0x{flash_size:x}")
            for old_start, old_end, old_name in ranges:
                if offset < old_end and old_start < end:
                    errors.append(f"line {line_no}: {name} overlaps {old_name}")
            ranges.append((offset, end, name))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("partition_file", type=Path)
    parser.add_argument("--flash-size", required=True, help="explicit size such as 2MB or 0x200000")
    args = parser.parse_args()
    errors = validate(args.partition_file, size_bytes(args.flash_size))
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"OK: {args.partition_file} fits in {args.flash_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
