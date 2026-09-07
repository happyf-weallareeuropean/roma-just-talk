"""Capture private raw output and sampled process RSS without interpreting it as neural RAM."""
import argparse
import json
from pathlib import Path
import subprocess
import threading
import time

import psutil


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--footprint", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    args.output.mkdir(parents=True, exist_ok=False)
    stopped = threading.Event()
    began = time.monotonic()
    profiler_jobs = []
    with (args.output / "stderr.txt").open("w") as errors, (args.output / "events.jsonl").open("w") as events:
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors, text=True, bufsize=1)
        process = psutil.Process(child.pid)

        def sample():
            with (args.output / "rss.jsonl").open("w") as output:
                while not stopped.is_set():
                    try:
                        m = process.memory_info()
                        c = process.cpu_times()
                        output.write(json.dumps({"seconds": time.monotonic() - began, "rss_bytes": m.rss,
                                                 "cpu_seconds": c.user + c.system}) + "\n")
                    except psutil.Error:
                        break
                    stopped.wait(0.02)

        thread = threading.Thread(target=sample)
        thread.start()
        for line in child.stdout:
            events.write(line)
            events.flush()
            try:
                event = json.loads(line)
            except ValueError:
                continue
            kind = event.get("event")
            if args.footprint and kind in ["baseline", "loaded", "idle_start"]:
                log = (args.output / f"footprint-{kind}.txt").open("w")
                profiler_jobs.append((subprocess.Popen(
                    ["footprint", "-p", str(child.pid), "--wide", "-j", str(args.output / f"footprint-{kind}.json")],
                    stdout=log, stderr=log), log))
        exit_code = child.wait()
        stopped.set()
        thread.join()
        for job, log in profiler_jobs:
            try:
                job.wait(timeout=15)
            except subprocess.TimeoutExpired:
                job.kill()
                job.wait()
            log.close()
    (args.output / "run.json").write_text(json.dumps({"command": command, "exit_code": exit_code,
                                                    "wall_seconds": time.monotonic() - began}, indent=2))
    print(json.dumps({"output": str(args.output), "exit_code": exit_code}), flush=True)
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
