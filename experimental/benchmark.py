#!/usr/bin/env python3
"""Compare full Alfred Script Filter latency and returned paths, not just engine time."""
import argparse
import json
import os
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def run(query, backend, env):
    e = dict(env)
    e["PATHFIND_BACKEND"] = "" if backend == "fd" else backend
    started = time.perf_counter_ns()
    process = subprocess.run(
        [str(ROOT / "pathfind-alfred.sh"), query],
        cwd=ROOT, env=e, capture_output=True, text=True, timeout=60,
    )
    elapsed = (time.perf_counter_ns() - started) / 1e6
    if process.returncode:
        raise RuntimeError(backend + ": " + process.stderr.strip())
    try:
        items = json.loads(process.stdout)["items"]
    except Exception as exc:
        raise RuntimeError(backend + ": invalid Alfred JSON: " + process.stderr) from exc
    paths = [item["arg"] for item in items if "arg" in item]
    return elapsed, paths

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("query", nargs="?", default="tax/2025")
    parser.add_argument("--runs", type=int, default=12)
    parser.add_argument("--mode", choices=["directory", "file", "mixed"], default="directory")
    parser.add_argument("--expected", help="Expected result path, to display its rank")
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")

    env = os.environ.copy()
    env["alfred_workflow_uid"] = "benchmark"  # avoid reading prefs.plist from CLI
    env["DEPS"] = "fd gawk jq"
    env["TYPE_OVERRIDE"] = "" if args.mode == "mixed" else args.mode
    env.setdefault("PATHFIND_PATHS", str(Path.home()))

    print("Query:", args.query)
    print("Roots:", repr(env["PATHFIND_PATHS"]))
    print("Mode:", args.mode, "- runs per backend:", args.runs)
    print("Note: first-run latency and later warmed queries are reported separately.\n")
    print(f'{"Backend":<9} {"first ms":>10} {"p50 ms":>10} {"p95 ms":>10} {"items":>8} {"expected rank":>14}')
    for backend in ["fd", "fsearch", "fff"]:
        try:
            measurements = []
            paths = []
            for _ in range(args.runs):
                ms, paths = run(args.query, backend, env)
                measurements.append(ms)
            ordered = sorted(measurements[1:] or measurements)
            p50 = statistics.median(ordered)
            p95 = ordered[max(0, int(len(ordered) * .95) - 1)]
            rank = (paths.index(args.expected) + 1) if args.expected in paths else "-"
            print(f"{backend:<9} {measurements[0]:>10.1f} {p50:>10.1f} {p95:>10.1f} {len(paths):>8} {str(rank):>14}")
            for item in paths[:3]:
                print("  ", item)
        except Exception as exc:
            print(backend + ": ERROR: " + str(exc))
            continue

if __name__ == "__main__":
    main()
