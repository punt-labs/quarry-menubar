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


