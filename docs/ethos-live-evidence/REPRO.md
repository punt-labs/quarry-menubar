# Quarry Menu Bar: Darwin live-verified handoff evidence

- Quarry commit: `f9ec901be2e7eb5cc562be57d00aff7d43fcb412`
- Ethos DES-086 follow-up: `7fa2922b6d420bbddede15563fc530f526b1e4a8`
- Host: arm64 macOS 26.6.2, Xcode 26.6 (17F113), SwiftFormat 0.64.7,
  SwiftLint 0.65.1, XcodeGen 2.48.0
- Koch reference: `de2778a90d9bdda56b1ee4e8c9e6018a58e04ba6`

This is a prototype on the real checkout, not a sandbox or a reusable Ethos
receipt. The sidecar uses the existing `linux-worktree-v1` profile ID with
`isolation: live-verified` for the approved Darwin live mode. No runtime
bundle is claimed or pinned for live mode; Ethos itself was not changed.

## Not proven here

The Python harness models the policy around a direct `make check`.
Real-hook parity was verified on Ethos
`devin/1795658354-darwin-worktree-runner` at
`4c246062490ab201d0666a20bd2742eb0df5bd37` against merged Quarry PR #89
(`d4679be57513a7722318185d108d305702b89758`); contributors need an
Ethos release containing the Darwin live-verified slice. Released
Ethos v5.2.3 ignores the sidecar and runs the existing live gate without
verification; the earlier sidecar-aware build `c837cd1` rejected it.
See [receipts.txt](receipts.txt) for the real-hook verdicts. Matching
exit codes alone do not establish parity if the failure causes differ.

## Replay the real Darwin hook

Use a disposable Quarry clone on an Apple Silicon Mac with Xcode at
`/Applications/Xcode.app` and the Homebrew SwiftFormat, SwiftLint and
XcodeGen in `/opt/homebrew/bin`. The sidecar declares these tools and
sets `USER` for XcodeGen's generated user data. It also puts XCTest's
DerivedData in the runner's external scratch directory. Build the runner from
a separate Ethos checkout. The Mac VM session acted as the stand-in
operator when approving `swift-default`. Use an interactive terminal
outside Claude Code and OpenCode; read the policy and type `yes` at the
prompt. Reapprove if either the check YAML or its snapshot sidecar changes.

```bash
e="$HOME/quarry-handoff-evidence"
ethos="$e/ethos-darwin"
quarry="$e/quarry-darwin"
operator_home="$e/operator-home"
ethos_ref=4c246062490ab201d0666a20bd2742eb0df5bd37
quarry_ref=d4679be57513a7722318185d108d305702b89758
(
set -e
mkdir -p "$e" "$operator_home"
git clone --branch devin/1795658354-darwin-worktree-runner \
  https://github.com/punt-labs/ethos.git "$ethos"
git -C "$ethos" switch --detach "$ethos_ref"
test "$(git -C "$ethos" rev-parse HEAD)" = "$ethos_ref"
go -C "$ethos" build -o "$e/ethos-live" ./cmd/ethos
git clone https://github.com/punt-labs/quarry-menubar.git "$quarry"
git -C "$quarry" switch --detach "$quarry_ref"
test "$(git -C "$quarry" rev-parse HEAD)" = "$quarry_ref"
cd "$quarry"
test -z "$(git --no-optional-locks status --porcelain)"
env -i HOME="$operator_home" PATH="$PATH" TERM="${TERM:-dumb}" \
  "$e/ethos-live" handoff approve-live swift-default
test -z "$(git --no-optional-locks status --porcelain)"
)
```

Prime the disposable clone's ignored output directories with `make check`.
Before and after each hook invocation, require empty
`git --no-optional-locks status --porcelain` output for clean, or only the
deliberate fixture edit for a broken case. Compare the fixture contents too.
Restore the fixture and check for an empty status again before continuing.
Do not accept a hook-induced write to a tracked file. Then on each case,
first run `make check` for the live verdict and invoke the hook:

```bash
cd "$quarry"
case_name=clean  # use broken or broken-xctest for the following replays
expected=0       # use 2 for either intentional break
rc=0
make check || rc=$?
test "$rc" -eq "$expected" && \
printf '{"session_id":"replay-%s","agent_id":"replay-agent","agent_type":"claude"}\n' \
  "$case_name" | HOME="$operator_home" CLAUDE_PROJECT_DIR="$quarry" \
  GIT_OPTIONAL_LOCKS=0 "$e/ethos-live" hook subagent-stop
```

For `broken`, append `let   quarryHandoffFormatProbe=0` on a new line
in `QuarryMenuBarTests/QuarryMenuBarTests.swift`. Restore the file, then for
`broken-xctest`, append `XCTFail("Deliberately broken handoff parity probe")`
after `XCTAssertNotNil(panel.body)` in that file. Restore it again after the
replay. Count `Check finished` records with `check=full-gate` and
`outcome=launched` in `$operator_home/.punt-labs/ethos/logs/ethos.log`
for each invocation and record `developer_fingerprint` from its verdict
record. The hook's process exit is not the gate's verdict.
See [receipts.txt](receipts.txt) for the actual outcomes and timings.

### Real-hook mutation

Use the same approved clone after restoring the test fixture. This probe
changes only `LICENSE`: the first marker gives the run a fresh cache key,
and the second is written after Ethos logs the gate launch. Run it only
in a disposable clone with no pre-existing edits.

```bash
(
  set -eo pipefail
  cd "$quarry"
  probe=$(mktemp -d "$e/mutation.XXXXXXXX")
  session="mutation-${probe##*.}"
  log="$operator_home/.punt-labs/ethos/logs/ethos.log"
  test -z "$(git --no-optional-locks status --porcelain)"
  cp LICENSE "$probe/LICENSE"
  writer=
  trap 'if [ -n "$writer" ]; then kill "$writer" 2>/dev/null || :; wait "$writer" || :; fi; cp "$probe/LICENSE" LICENSE' EXIT
  printf '\nopening probe %s\n' "$session" >> LICENSE
  test "$(git --no-optional-locks status --porcelain)" = ' M LICENSE'
  (
    for ((i=0; i<300; i++)); do
      if awk -v id="session_id=$session " \
        'index($0, id) && /check=full-gate outcome=launched / { found=1 } END { exit !found }' "$log"; then
        printf '\nmid-run probe %s\n' "$session" >> LICENSE
        touch "$probe/injected"
        exit 0
      fi
      sleep 0.1
    done
    exit 1
  ) &
  writer=$!
  printf '{"session_id":"%s","agent_id":"replay-agent","agent_type":"claude"}\n' "$session" |
    HOME="$operator_home" CLAUDE_PROJECT_DIR="$quarry" GIT_OPTIONAL_LOCKS=0 \
      "$e/ethos-live" hook subagent-stop > "$probe/hook.json"
  wait "$writer"
  writer=
  test -f "$probe/injected"
  test "$(git --no-optional-locks status --porcelain)" = ' M LICENSE'
  cp "$probe/LICENSE" LICENSE
  trap - EXIT
  test -z "$(git --no-optional-locks status --porcelain)"
  jq -e '.systemMessage | startswith("handoff checks deferred (full-gate): checkout changed (key mismatch) during the live-verified check at \"LICENSE\".")' \
    "$probe/hook.json"
  cat "$probe/hook.json"
)
```

## Historical results before root child-entry watches

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

Use a dedicated clean Mac checkout of this branch and the standard repo
tools. The commit IDs in receipts identify the historical runs. Copy the
helpers outside the checkout so the evidence does not become a keyed input. The overlay
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
make -C "$quarry" check
QUARRY_EVIDENCE_ETHOS="$ethos" python3 "$e/run.py" "$quarry"
```

Optional arguments after the Quarry path select
`clean`, `broken`, `broken-xctest`, `mid-run-edit`, `dropped-events`, `check-writes`,
`new-swift-source`, or `new-root-swift-source`. The standalone check primes
the ignored output directories; a fresh checkout may defer if the first
guarded invocation creates them. `broken` asserts the SwiftFormat fixture
failure. `broken-xctest` asserts that XcodeBuild exits 65 on the deliberately
failing `ContentPanelTests.testContentPanelInitializesWhenConnected()`.
GNU Make reports either failed recipe as exit 2.
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
worktree-local Git directory. Ancestor watches catch path replacement;
the root and directories directly containing keyed files also watch
child entries for `NOTE_WRITE` and `NOTE_EXTEND`. Git directory watches
include child changes: creating and removing a name sets `NOTE_WRITE`
even when no callback names the vanished child.
Successful arming precedes the starting key; a changed inventory while
arming invalidates the evidence. Watches are drained after the closing
key and FSEvents flush. Inability to arm/read the watches never produces
a verified result.

`new-swift-source` and `new-root-swift-source` run the full gate and create
and remove a `.swift` file during the test phase, under `QuarryMenuBar/Views`
and at the checkout root respectively. Before either probe, the same harness
invocation must observe a guarded clean pass; it runs that control automatically
if needed. The probe itself disables FSEvents and requires equal keys, a quiet
parent until injection, and a child-entry vnode note on that exact parent:

```bash
for trial in $(seq 1 20); do
  python3 "$e/run.py" "$quarry" new-swift-source new-root-swift-source || break
done
```

Root child-entry watches remain strict: a directory vnode does not
identify the child that changed. Previously, regenerating the ignored
root `QuarryMenuBar.xcodeproj` deferred a successful clean gate. The
Make targets still regenerate unconditionally, but under the existing
ignore rule for `build/`; XcodeBuild explicitly uses the project in
`build/xcodegen/`. Once output directories exist, replacing the generated
project does not rewrite the checkout root. Xcode also writes under
`DerivedData/`, but does not replace that directory in a primed tree.
XcodeGen's `--use-cache`
was rejected because it kept an independently modified project file
when the spec and source inventory were unchanged.

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
Waiting for a closing key may give FSEvents time to catch up; an event ID
does not itself prove that every completed filesystem operation has
already been returned by the watcher.

See [receipts.txt](receipts.txt) for the exact counts. With the mutation
before the closing key, the modeled Koch cutoff caught every keyed,
`HEAD`, and `index` trial. With the mutation after that key but before the
cutoff, the same decision missed in-scope changes. The vnode guard
deferred for every trial in both windows. A live-verified runner should
keep FSEvents for coverage flags and use the independently armed guard
to veto a pass or failure when it records a mutation.

The prototype is fail-closed for these tested changes; it makes no claim
that watching a live checkout is equivalent to filesystem isolation. The
Linux-only runner slice at Ethos `46f9e23` is not used for this Mac proof;
the pinned Darwin follow-up above supplies the actual tree-key functions.

Run the repeated probes only in a disposable clone. They intentionally
replace and restore the clone's real `HEAD` and `index`:

```bash
git clone --local --no-hardlinks "$quarry" "$e/probe-checkout"
python3 "$e/probe.py" "$e/probe-checkout"
python3 "$e/probe.py" "$e/probe-checkout" --closing-key
python3 "$e/probe.py" "$e/probe-checkout" --after-key
python3 "$e/probe.py" "$e/probe-checkout" --chmod
```

The fast mode captures an immediate cutoff and verifies the real keys at
the end of each 20-trial batch. Closing-key mode resamples the actual keys
after the mutation and before every individual cutoff, and also tests the
clone's `HEAD` and `index`. The after-key mode tests a mutation in the
window between the actual closing key and the cutoff. Each probe requires
the expected vnode path and mutation bit, not merely a concurrent event.

The chmod mode changes and restores a mode bit on a keyed file and the
clone's index, 20 trials each. It resamples the tree keys after each
change/restore and explicitly requires the vnode-only verdict to defer
on a standalone `NOTE_ATTRIB`. To reproduce the clean controls, run
`python3 "$e/run.py" "$quarry" clean` three times on the real checkout.
The clean controls at `757566bd4126e455a04c836751f3328bf19033bf` each
armed 285 vnode descriptors and passed after suppressing an index
atime-only notification. Both chmod series in the disposable clone
deferred 20/20 with 229 descriptors. See [receipts.txt](receipts.txt)
for the individual gate timings.

The gate command is `make check` throughout. Its format, lint, and test
requirements and the active check YAML are unchanged. For the check-write
probe only, GNU Make's `MAKEFILES`
loads an external extra prerequisite (`probe.mk`) that writes and restores
`LICENSE`; all original gate prerequisites still run. This demonstrates
deferral for a write by the gate process tree without modifying the real
Makefile. The independent mid-run edit comes from the harness after
`Running unit tests...` appears.

## Deferral rate with concurrent Git readers

The harness sets `GIT_OPTIONAL_LOCKS=0` for `make check` and its children,
not for other sessions. It still defers on `.git/index.lock` activity.
Repeat clean trials sequentially, saving each receipt even if the
harness exits nonzero for a deferral:

```bash
clean_series() {
  for n in $(seq -w 1 10); do
    rm -f "$e/clean.json"
    python3 "$e/run.py" "$quarry" clean || :
    jq -e '.exit == 0' "$e/clean.json" >/dev/null || return 1
    mv "$e/clean.json" "$e/$1-$n.json"
  done
  jq -s 'group_by([.verdict, .reason]) | map({verdict: .[0].verdict,
    reason: .[0].reason, trials: length})' "$e/$1"-[0-9][0-9].json
}
busy_series() (
  (
    while :; do
      git -C "$quarry" status >/dev/null
      git -C "$quarry" diff --stat >/dev/null
      sleep "$((RANDOM % 3 + 1))"
    done
  ) &
  agent=$!
  trap 'kill "$agent" 2>/dev/null || :; wait "$agent" 2>/dev/null || :' EXIT
  clean_series "$1"
)
clean_series quiet
(unset GIT_OPTIONAL_LOCKS; busy_series busy)
(export GIT_OPTIONAL_LOCKS=0; busy_series readonly)
```

The default-reader trials saw `index.lock` and the `.git` directory
vnode notification, but no index replacement event. The checked-in
guard does not treat equal opening and closing index entries as evidence
that all intermediate versions were seen. In a separate scratch probe,
we performed 20 atomic `index.lock`-to-`index` replacements per trial,
took the event-ID cutoff immediately after the burst, and deduplicated
lock creation records by event ID. FSEvents undercounted on all 20
trials without reporting loss; the directory vnode did not provide a
creation count either. A rule that trusts those counts could allow an
unseen staged version to pass. The strict veto remains in place.

The safer mitigation is to set `GIT_OPTIONAL_LOCKS=0` for read-only
Git commands in the other sessions, not to ignore observed lock activity.
See [receipts.txt](receipts.txt) for the measured rates and the strict
guard's Git staging regressions.
