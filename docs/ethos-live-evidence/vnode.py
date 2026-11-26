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


class VnodeWatch:
    def __init__(self):
        try:
            self.queue = select.kqueue()
        except OSError as error:
            raise VnodeUnavailable(f"cannot create vnode guard: {error}") from error
        self.paths = {}
        self.original = {}
        self.atime_only = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.queue.close()
        for fd in self.paths:
            os.close(fd)

    def arm(self, paths):
        soft_limit, _ = resource.getrlimit(resource.RLIMIT_NOFILE)
        budget = MAX_WATCH_FDS if soft_limit == resource.RLIM_INFINITY else min(
            MAX_WATCH_FDS, soft_limit // 2
        )
        if len(paths) > budget:
            raise VnodeUnavailable("keyed set too large for vnode guard")
        try:
            self._register(paths)
        except OSError as error:
            raise VnodeUnavailable(f"cannot arm vnode guard: {error}") from error

    def _register(self, paths):
        changes = []
        for path, notes in paths.items():
            fd = os.open(path, os.O_EVTONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
            self.paths[fd] = path
            self.original[fd] = os.fstat(fd)
            changes.append(select.kevent(
                fd, filter=select.KQ_FILTER_VNODE, flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                fflags=notes,
            ))
        self.queue.control(changes, 0, 0)

    def events(self):
        receipt = []
        while batch := self.queue.control(None, len(self.paths), 0):
            for event in batch:
                if event.flags & select.KQ_EV_ERROR or not event.fflags:
                    raise OSError(f"incomplete vnode notification: {event}")
                record = {"path": str(self.paths[event.ident]), "notes": event.fflags}
                if event.fflags == select.KQ_NOTE_ATTRIB and self.only_atime(event.ident):
                    self.atime_only.append(record)
                else:
                    receipt.append(record)
        return receipt

    def only_atime(self, fd):
        before, after = self.original[fd], os.fstat(fd)
        return before.st_atime_ns != after.st_atime_ns and all(
            getattr(before, name) == getattr(after, name) for name in STABLE
        )
