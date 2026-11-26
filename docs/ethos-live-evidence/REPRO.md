# Quarry Menu Bar: Darwin live-verified handoff evidence

- Quarry commit: `f9ec901be2e7eb5cc562be57d00aff7d43fcb412`
- Ethos DES-086 follow-up: `7fa2922b6d420bbddede15563fc530f526b1e4a8`
- Host: arm64 macOS 26.6.2, Xcode 26.6 (17F113), SwiftFormat 0.64.7,
  SwiftLint 0.65.1, XcodeGen 2.48.0
- Koch reference: `de2778a90d9bdda56b1ee4e8c9e6018a58e04ba6`

This is a prototype on the real checkout, not a sandbox or a reusable Ethos
receipt. The sidecar uses the existing `linux-worktree-v1` profile ID with
`isolation: live-verified` for the approved Darwin live mode. Ethos still
needs parser and runner support for this isolation value. No runtime
bundle is claimed or pinned for live mode; Ethos itself was not changed.

## Results

| Scenario | Verdict | `make check` exit | Gate time |
| --- | --- | ---: | ---: |
| Clean checkout | Pass | 0 | 10.32 s |
| SwiftFormat violation in tracked test source | Fail | 2 | 0.14 s |
| External edit and restore during XCTest | Deferred | 0 | 13.87 s |
| Injected FSEvents loss during XCTest | Deferred | 0 | 10.09 s |
| Check writes and restores tracked file | Deferred | 0 | 11.19 s |

All five guarded runs had equal before/after Ethos checkout-state and source-proof
keys within the run, covering 128 keyed paths. The broken tree's keys differed
from the clean tree's. The write cases each had two real FSEvents for
`LICENSE` and one independent vnode notification. The drop case had one synthetic event with the documented
`KernelDropped | MustScanSubDirs` flags, fed into the same collector as the
OS callback; it was not a forced kernel overflow.

Uninstrumented baseline `make check` on the parent commit passed in 41.09 s.
The guarded clean run reused local DerivedData. The original watched clean
run's Xcode result bundle reported 134 cases: 133 passed, zero failures,
one existing skip.

## Reproduce

Use a dedicated clean Mac checkout at the Quarry commit above and the
standard repo tools. Copy the helpers into a directory outside the
checkout so the evidence will not become a new keyed input. The overlay
adds a test only to the compiler's view; it does not change Ethos files.

```bash
e="$HOME/quarry-handoff-evidence"
ethos="$HOME/repos/ethos-quarry-evidence"
quarry="$HOME/repos/quarry-menubar"
mkdir -p "$e"
cp keys_test.go probe.mk probe.py run.py vnode.py watch.swift "$e/"
git -C "$HOME/repos/ethos" fetch origin devin/1795659068-darwin-worktree-argv
git -C "$HOME/repos/ethos" worktree add --detach "$ethos" \
  7fa2922b6d420bbddede15563fc530f526b1e4a8
python3 - "$e" "$ethos" <<'PY'
import json
from pathlib import Path
import sys
e, ethos = map(Path, sys.argv[1:])
overlay = {str(ethos / "internal/hook/quarry_live_keys_test.go"): str(e / "keys_test.go")}
(e / "overlay.json").write_text(json.dumps({"Replace": overlay}))
PY
(
  cd "$ethos"
  go build -o "$e/ethos" ./cmd/ethos
  go test -c -overlay "$e/overlay.json" -o "$e/keys.test" ./internal/hook
)
swiftc "$e/watch.swift" -o "$e/watch"
QUARRY_EVIDENCE_ETHOS="$ethos" python3 "$e/run.py" "$quarry"
```

Optional arguments after the Quarry path select
`clean`, `broken`, `mid-run-edit`, `dropped-events`, or `check-writes`.
Each run writes a gate log and a JSON evidence file beside the harness.

## Closing the transient-event gap

The first watcher missed immediate create/remove in `.git`. We reproduced
the miss with the original stream flags (`FileEvents`, `NoDefer`,
`WatchRoot`), a 50 ms latency, and confirmed stream startup. Watching
`.git` alone still missed it. With both roots watched, the immediate flush
matched 3/10 paths and waiting 150 ms after stream startup still matched
0/10. Waiting 150 ms **after the operation** matched 10/10 without
changing the mutation. No loss flags were sent. The raw callback omitted
the path, so path filtering was not the cause. The evidence locates the
gap at publication/delivery before the final flush; it does not isolate
which internal FSEvents stage buffered the event.

The harness keeps the original FSEvents path and coverage checks, now with
a second, independent `EVFILT_VNODE` guard. It opens the keyed files and their
ancestor directories, the checkout's `.git` entry, and the complete
worktree-local Git directory. Ancestor watches catch path replacement,
without deferring for ordinary ignored child creation by XcodeGen. Git
directory watches include child changes: creating and removing a name
sets `NOTE_WRITE` even when no callback names the vanished child.
Successful arming precedes the starting key; a changed inventory while
arming invalidates the evidence. Watches are drained after the closing
key and FSEvents flush. Inability to arm/read the watches never produces
a verified result.

The watch budget is the smaller of 4,096 descriptors and half the soft
`RLIMIT_NOFILE` (4,096 if the soft limit is unlimited). It counts the
entire deduplicated watch set, including ancestors and Git metadata.
An over-budget set defers before opening path descriptors; no paths
are dropped. An error opening or arming a watch also defers, with the
OS error in the reason. These deferrals do not run the gate and record
null gate exit and time in the JSON receipt.

To reproduce the budget deferral with the same checkout and harness:

```bash
status=0
(ulimit -Sn 256 && python3 "$e/run.py" "$quarry" clean) || status=$?
test "$status" -eq 1
jq -e '.verdict == "deferred" and .reason == "keyed set too large for vnode guard"
       and .exit == null and .gate_seconds == null' "$e/clean.json"
```

Run the same command without the reduced limit for the clean control.
Avoid concurrent Git operations on that checkout during the run.

The starting/closing Git reads can generate `NOTE_ATTRIB`: they advanced
the access times of index/object files with all other measured metadata
unchanged. Only that exact case is disregarded, not content writes,
renames, directory writes, or attribute events with a changed ctime,
mtime, mode, flags, UID, GID, size, device, inode, or link count. JSON
receipts list the suppressed atime-only notifications separately from
vetoes and record the number of armed vnode file descriptors.

The cutoff comparison in `probe.py` models the **described** Koch policy:
use keyed paths plus this worktree's own `HEAD` and `index`; sample a
global FSEvents event ID after the closing tree key and count coverage
flags as fired. Koch's reference commit only contains a sidecar, so its
watcher code was not available to run here. The original arbitrary
`.git` probe name is outside the described Koch scope. Its final state
and keys are identical and this fixture itself is not a gate input, but
the same publication gap affects actual keyed-file notifications too.
