import json
import os
from pathlib import Path
import select
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory

from run import GAP, HERE, contains, decide, git, keys, mutate
from vnode import VnodeWatch, watch_paths

TRIALS = 20


def exercise(root, gitdir, scratch, name, index):
    inside = gitdir / "info" / f"quarry-evidence-probe-{index}"
    outside = scratch / inside.name
    if name == "git-create-remove":
        with inside.open("xb") as file:
            file.write(b"vnode probe")
        inside.unlink()
        return inside.parent, select.KQ_NOTE_WRITE
    elif name == "git-rename-in-out":
        outside.rename(inside)
        inside.rename(outside)
        return inside.parent, select.KQ_NOTE_WRITE
    else:
        target, operation = name.split(":", 1)
        path = root / "LICENSE" if target == "keyed" else gitdir / target
        if operation == "write-restore":
            length = path.stat().st_size
            try:
                mutate(path, b"vnode probe")
            finally:
                os.truncate(path, length)
            return path, select.KQ_NOTE_WRITE
        elif operation == "chmod-restore":
            mode = stat.S_IMODE(path.stat().st_mode)
            try:
                path.chmod(mode ^ stat.S_IXGRP)
            finally:
                path.chmod(mode)
            return path, select.KQ_NOTE_ATTRIB
        else:
            path.rename(outside)
            try:
                with path.open("xb") as file:
                    file.write(b"replacement probe")
                path.unlink()
            finally:
                outside.rename(path)
            return path, select.KQ_NOTE_RENAME


def probe(root, gitdir, scratch, name, key, phase):
    watched = watch_paths(root, key["paths"], gitdir)
    trials = []
    for index in range(TRIALS):
        (scratch / f"quarry-evidence-probe-{index}").touch(exist_ok=True)
        with VnodeWatch() as guard, subprocess.Popen(
            [HERE / "watch", root, gitdir],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        ) as watcher:
            assert watcher.stdout.readline().strip() == "ready"
            guard.arm(watched)
            if phase == "after-key":
                assert keys(root) == key
            target, note = exercise(root, gitdir, scratch, name, index)
            if phase in ("closing-key", "chmod"):
                assert keys(root) == key
            watcher.stdin.write("cutoff\n")
            watcher.stdin.flush()
            cutoff = int(watcher.stdout.readline().strip())
            raw, _ = watcher.communicate("finish\n", timeout=15)
            assert watcher.returncode == 0
            events = json.loads(raw)
            vnode_events = guard.events()
        old, _, relevant = decide(root, gitdir, key, key, events, [], 0)
        scoped = [
            event for event in events
            if event["flags"] & GAP or (
                event["id"] <= cutoff and (
                    not contains(gitdir, Path(event["path"]))
                    or any(contains(Path(event["path"]), gitdir / file) for file in ("HEAD", "index"))
                )
            )
        ]
        bounded, _, _ = decide(root, gitdir, key, key, scoped, [], 0)
        new, _, _ = decide(root, gitdir, key, key, events, vnode_events, 0)
        if phase == "chmod":
            vnode_only, _, _ = decide(root, gitdir, key, key, [], vnode_events, 0)
            assert vnode_only == "deferred" and any(
                event == {"path": str(target), "notes": select.KQ_NOTE_ATTRIB}
                for event in vnode_events
            ), vnode_events
        trials.append({
            "old": old, "scoped_cutoff": bounded, "guarded": new, "cutoff": cutoff,
            "relevant": relevant, "vnode": vnode_events,
            "vnode_fds": len(guard.paths), "atime_only_vnode_events": guard.atime_only,
        })
        assert new == "deferred" and any(
            event["path"] == str(target) and event["notes"] & note for event in vnode_events
        ), trials[-1]
    assert keys(root) == key, f"{name} did not restore the keyed inputs"
    return trials


def main(root, phase):
    gitdir = Path(git(root, "rev-parse", "--absolute-git-dir")).resolve(strict=True)
    if git(root, "status", "--porcelain=v1", "--untracked-files=all"):
        raise RuntimeError("start from a clean checkout")
    key = keys(root)
    names = ("git-create-remove", "git-rename-in-out", "keyed:write-restore", "keyed:replace-restore")
    if phase == "closing-key":
        names += ("HEAD:write-restore", "HEAD:replace-restore", "index:write-restore", "index:replace-restore")
    elif phase == "after-key":
        names = ("keyed:write-restore", "HEAD:replace-restore", "index:replace-restore")
    elif phase == "chmod":
        names = ("keyed:chmod-restore", "index:chmod-restore")
    with TemporaryDirectory(dir=HERE, prefix="quarry-probe-") as directory:
        results = {}
        for name in names:
            trials = probe(root, gitdir, Path(directory), name, key, phase)
            results[name] = trials
            print(
                f"{name}: FSEvents-only deferred {sum(t['old'] == 'deferred' for t in trials)}"
                f"/{TRIALS}; scoped cutoff deferred {sum(t['scoped_cutoff'] == 'deferred' for t in trials)}"
                f"/{TRIALS}; guarded deferred {sum(t['guarded'] == 'deferred' for t in trials)}"
                f"/{TRIALS}; unchanged Ethos keys", flush=True,
            )
    receipt = {"head": git(root, "rev-parse", "HEAD"), "phase": phase, "key": key, "trials": results}
    suffix = "" if phase == "fast" else f"-{phase}"
    (HERE / f"transient-probes{suffix}.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    phase = sys.argv[2].removeprefix("--") if len(sys.argv) > 2 else "fast"
    if phase not in ("fast", "closing-key", "after-key", "chmod"):
        raise ValueError(f"unknown phase: {phase}")
    main(Path(sys.argv[1]).resolve(strict=True), phase)
