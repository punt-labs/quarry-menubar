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


