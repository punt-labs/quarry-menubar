import json
import os
from pathlib import Path
import subprocess
import sys
import time

from vnode import VnodeUnavailable, VnodeWatch, watch_paths

HERE = Path(__file__).resolve().parent
ETHOS = Path(os.environ.get("QUARRY_EVIDENCE_ETHOS", Path.home() / "repos/ethos-quarry-evidence"))
SCENARIOS = ("clean", "broken", "mid-run-edit", "dropped-events", "check-writes")
EDIT = b"\nquarry live evidence probe\n"
GAP = 0x0F | 0x20 | 0x40 | 0x80


def mutate(path, content):
    with path.open("ab") as file:
        file.write(content)


def write_probe(path):
    original = path.stat().st_size
    try:
        mutate(path, EDIT)
        time.sleep(0.3)
    finally:
        os.truncate(path, original)
    print(f"quarry evidence: wrote and restored {path}", flush=True)


def git(root, *args):
    return subprocess.check_output(
        ["git", "--no-optional-locks", "-C", root, *args], text=True
    ).strip()


def keys(root):
    output = subprocess.check_output(
        [HERE / "keys.test", "-test.run", "^TestQuarryLiveTreeKeys$", "-test.v"],
        cwd=ETHOS / "internal/hook",
        env={**os.environ, "QUARRY_EVIDENCE_ROOT": str(root)},
        text=True,
    )
    prefix = "QUARRY_TREE_KEYS "
    return json.loads(next(line[len(prefix):] for line in output.splitlines()
                           if line.startswith(prefix)))


def contains(parent, child):
    return child == parent or parent in child.parents


def decide(root, gitdir, before, after, events, vnode_events, code):
    keyed = {root / path for path in before["paths"] + after["paths"]}
    relevant = []
    for event in events:
        if event["flags"] == 0x10:  # HistoryDone is a stream marker, not a mutation.
            continue
        path = Path(event["path"])
        if event["flags"] & GAP or contains(gitdir, path) or any(
            contains(path, source) for source in keyed
        ):
            relevant.append(event)
    if any(event["flags"] & GAP for event in relevant):
        verdict, reason = "deferred", "FSEvents loss/coverage flag"
    elif relevant or vnode_events or before != after:
        verdict, reason = "deferred", "keyed input or Git metadata changed"
    elif code < 0 or code in {129, 130, 137, 143}:
        verdict, reason = "deferred", "gate interrupted"
    elif code == 0:
        verdict, reason = "pass", "unchanged inputs"
    else:
        verdict, reason = "fail", "unchanged inputs"
    return verdict, reason, relevant


def scenario(root, name):
    try:
        guarded_scenario(root, name)
    except VnodeUnavailable as error:
        result = {
            "scenario": name, "verdict": "deferred", "reason": str(error),
            "exit": None, "gate_seconds": None,
        }
        (HERE / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n")
        raise SystemExit(f"{name}: deferred: {error} (gate not run)") from None


def guarded_scenario(root, name):
    env = dict(os.environ)
    for key in ("MAKEFLAGS", "MFLAGS", "MAKEFILES", "GNUMAKEFLAGS"):
        env.pop(key, None)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    gitdir = Path(git(root, "rev-parse", "--absolute-git-dir")).resolve(strict=True)
    if name == "check-writes":
        env.update(MAKEFILES=str(HERE / "probe.mk"), QUARRY_EVIDENCE_SCRIPT=__file__)
    log_path = HERE / f"{name}.log"
    with (HERE / f"{name}.watch.stderr").open("w") as watcher_log, VnodeWatch() as guard:
        watcher = subprocess.Popen(
            [HERE / "watch", root, gitdir],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=watcher_log, text=True,
        )
        try:
            if watcher.stdout.readline().strip() != "ready":
                raise RuntimeError("failed to start FSEvents")
            inventory = keys(root)
            guard.arm(watch_paths(root, inventory["paths"], gitdir))
            before = keys(root)
            if inventory != before:
                raise RuntimeError("deferred: checkout changed while arming vnode watches")
            start = time.monotonic()
            with log_path.open("wb") as log:
                with subprocess.Popen(["make", "check"], cwd=root, env=env,
                                      stdout=log, stderr=subprocess.STDOUT) as gate:
                    if name in ("mid-run-edit", "dropped-events"):
                        deadline = start + 45
                        while b"Running unit tests..." not in log_path.read_bytes():
                            if gate.poll() is not None or time.monotonic() > deadline:
                                raise RuntimeError("did not reach Xcode while gate was running")
                            time.sleep(0.02)
                        if gate.poll() is not None:
                            raise RuntimeError("gate already completed before injection")
                        if name == "mid-run-edit":
                            write_probe(root / "LICENSE")
                        else:
                            watcher.stdin.write("drop\n")
                            watcher.stdin.flush()
                            if watcher.stdout.readline().strip() != "injected":
                                raise RuntimeError("loss injection was not acknowledged")
                        if gate.poll() is not None:
                            raise RuntimeError("gate already completed during injection")
                    code = gate.wait()
            elapsed = round(time.monotonic() - start, 2)
            after = keys(root)
            output, _ = watcher.communicate("finish\n", timeout=15)
            if watcher.returncode != 0:
                raise RuntimeError("FSEvents watcher failed")
            events = json.loads(output)
            vnode_events = guard.events()
        finally:
            if watcher.poll() is None:
                watcher.kill()
                watcher.wait()
    verdict, reason, relevant = decide(root, gitdir, before, after, events, vnode_events, code)
    result = {
        "scenario": name, "verdict": verdict, "reason": reason,
        "exit": code, "gate_seconds": elapsed, "head": git(root, "rev-parse", "HEAD"),
        "gitdir": str(gitdir), "before": before, "after": after,
        "relevant_events": relevant, "vnode_events": vnode_events,
        "vnode_fds": len(guard.paths), "atime_only_vnode_events": guard.atime_only,
        "ignored_event_count": len(events) - len(relevant),
    }
    (HERE / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{name}: {verdict}, exit {code}, {elapsed:.2f}s, "
          f"FSEvents={len(relevant)}, vnode events={len(vnode_events)}, "
          f"vnode fds={len(guard.paths)}, atime-only={len(guard.atime_only)}, "
          f"keys equal={before == after}", flush=True)
    expected = {"clean": "pass", "broken": "fail"}.get(name, "deferred")
    if verdict != expected or (name != "broken" and code != 0):
        raise RuntimeError(f"expected {expected} ({name}); see {log_path}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "write":
        write_probe(Path(sys.argv[2]))
    else:
        root = Path(sys.argv[1]).resolve(strict=True)
        for name in sys.argv[2:] or SCENARIOS:
            if name not in SCENARIOS:
                raise ValueError(f"unknown scenario: {name}")
            if git(root, "status", "--porcelain=v1", "--untracked-files=all"):
                raise RuntimeError("start from a clean checkout")
            if name == "broken":
                path = root / "QuarryMenuBarTests/QuarryMenuBarTests.swift"
                size = path.stat().st_size
                try:
                    mutate(path, b"\nlet   quarryHandoffFormatProbe=0\n")
                    # This deliberately dirty input is setup, before the guarded interval.
                    time.sleep(0.3)
                    scenario(root, name)
                finally:
                    os.truncate(path, size)
            else:
                scenario(root, name)
            if git(root, "status", "--porcelain=v1", "--untracked-files=all"):
                raise RuntimeError("checkout was not restored")
