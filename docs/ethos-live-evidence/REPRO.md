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

