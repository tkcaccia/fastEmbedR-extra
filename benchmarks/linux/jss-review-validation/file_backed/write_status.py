#!/usr/bin/env python3
import csv
import pathlib
import sys


def main():
    target = pathlib.Path(sys.argv[1])
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        return
    with target.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=("id", "status", "error"))
        writer.writeheader()
        writer.writerow({"id": sys.argv[2], "status": sys.argv[3],
                         "error": sys.argv[4]})


if __name__ == "__main__":
    main()
