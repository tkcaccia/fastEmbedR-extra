"""Allocation-only diagnostic for Slurm's per-job memory counters."""

from pathlib import Path


def main() -> None:
    for line in Path("/proc/self/cgroup").read_text().splitlines():
        if not line.startswith("0::"):
            continue
        path = Path("/sys/fs/cgroup") / line.split("::", 1)[1].lstrip("/")
        print(f"cgroup_path={path}")
        for name in ("memory.max", "memory.current", "memory.peak"):
            item = path / name
            value = item.read_text().strip() if item.is_file() else "missing"
            print(f"{name}={value}")


if __name__ == "__main__":
    main()
