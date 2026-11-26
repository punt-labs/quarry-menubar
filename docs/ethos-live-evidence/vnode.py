import os
from pathlib import Path
import resource
import select

NOTES = (
    select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND | select.KQ_NOTE_ATTRIB
    | select.KQ_NOTE_DELETE | select.KQ_NOTE_LINK | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE
)
REPLACED = select.KQ_NOTE_DELETE | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE
MAX_WATCH_FDS = 4096
STABLE = (
    "st_dev", "st_ino", "st_mode", "st_size", "st_mtime_ns", "st_ctime_ns",
    "st_uid", "st_gid", "st_flags", "st_nlink",
)


class VnodeUnavailable(RuntimeError):
    pass


def raise_walk_error(error):
    raise VnodeUnavailable(f"cannot enumerate vnode watches: {error}") from error


def watch_paths(root, keyed, gitdir):
    paths = {root: REPLACED}
    for name in keyed:
        path = root / name
        for parent in path.parents:
            if root in parent.parents:
                paths.setdefault(parent, REPLACED)
        paths[path] = NOTES
    paths[root / ".git"] = NOTES
    paths[gitdir] = NOTES
    for directory, dirs, files in os.walk(gitdir, onerror=raise_walk_error):
        for name in dirs + files:
            paths[Path(directory) / name] = NOTES
    return paths


