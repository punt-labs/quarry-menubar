# quarry-menubar Design Decision Log

Architecture Decision Records for the Quarry macOS menu bar app. Each ADR
records a decision, why it was made, the alternatives rejected, and its status.
The app is a **pure Quarry client** — a Swift reimplementation of quarry's
client tier (see the sibling `../quarry/DESIGN.md`, DES-031). Reference for the
testable-by-design patterns below: `../koch-trainer-swift`.

## Rules

- One ADR per decision that has a rejected alternative. Trivial choices do not
  get an ADR.
- Status is `Accepted` (implemented), `Proposed` (decided, not yet built — track
  with a bead), or `Superseded by ADR-NNN`.
- When a decision changes, add a new ADR that supersedes the old one; do not
  rewrite history.

---

## ADR-001: Thin Views, logic in injectable models (testable by design)

**Status:** Accepted (partially applied — see ADR-004/ADR-005 for the gaps).

### Decision

SwiftUI `View`s are declarative and side-effect-free. All business logic —
network calls, connection resolution, search, detail loading, text formatting —
lives in `@MainActor` models (`@Observable`/`ObservableObject`) and services that
are **injected via defaulted initializers** (`init(dep: Protocol = Default())`).
App-lifetime state is owned at app scope, not created inside a view. A view's
`.task`/`.onAppear` may only *delegate* to a model method; it never contains
logic.

### Why

Testability and correctness are the same property here. When logic lives in a
model behind a protocol seam, a test substitutes a fake, drives the model's
public methods, and asserts on a published state enum — no simulator, no real
network, no UI automation. When logic lives in a view, neither is possible:
`../koch-trainer-swift` demonstrates the working shape
(`ReceiveTrainingViewModel.swift:13-16` constructor injection;
`MorseAudioEngine.swift:8-46` protocol seam; `SilentAudioEngine.swift`
call-recorder fake) at ~88% adjusted coverage.

### Alternatives

1. **Logic in Views (`.task`/`.onAppear`/static funcs on the View).** Rejected.
   This caused the v0.6.1 connect regression (ADR-004) and forces static-function
   test workarounds (ADR-005). It is the exact anti-pattern this ADR exists to
   prevent.
2. **UI-automation tests as the primary coverage.** Rejected as the *primary*
   mechanism — slow and flaky. UI tests cover what genuinely cannot be unit
   tested (window lifecycle); everything else is unit-tested at the model seam.

---

## ADR-002: Own the Quarry connection at app scope, not in a view's `.task`

**Status:** Accepted (implemented — the fix this file's creation accompanies).

### Decision

An `AppDelegate` (`@NSApplicationDelegateAdaptor`) owns the app-lifetime
`ConnectionManager` and starts the initial connect from
`applicationDidFinishLaunching`. `connectIfNeeded()` runs the network work on a
**manager-owned unstructured `Task`** that outlives every panel. A cancelled
refresh (`CancellationError`/`URLError.cancelled`) resets to `.idle` — never a
user-facing `.unavailable`.

### Why

`MenuBarExtra(.window)` builds its label and window content lazily and **cancels
the panel's `.task` on every window teardown**. The connect was originally driven
from `ContentPanel`'s `.task`; opening then closing the panel cancelled the
in-flight `URLSession` request, `mapURLError` turned the cancel into
`CancellationError`, and the catch-all surfaced it as "Quarry Unavailable —
CancellationError" with the `.idle` guard blocking any retry. The Quarry 2.0
loopback path (synchronous `serve.port`/`serve.token` reads before the awaits)
widened the window enough to make it hit on every launch. `applicationDidFinish`
`Launching` is the one lifecycle hook that fires once at startup independent of
any window.

### Alternatives

1. **Connect from the scene/panel `.task`.** Rejected — the bug above.
2. **View-scoped `@StateObject` connection model** (as `../koch-trainer-swift`
   does for its *session* VMs, `ReceiveTrainingView.swift:134`). Rejected for a
   menu-bar connection: a training session *should* die when its screen leaves,
   but a connection must not die when the menu panel closes. This is the one
   place quarry-menubar deliberately goes beyond the koch reference — app-scope
   ownership, mirroring koch's own app-scope stores (`KochTrainerApp.swift:28-30`).

---

## ADR-003: Connection resolution mirrors quarry's `TargetResolver`/`ClientConfig`

**Status:** Accepted.

### Decision

`ConnectionProfileLoader` resolves a connection the way the `quarry` CLI does
(`../quarry/src/quarry/client/`): a **remote** `~/.punt-labs/mcp-proxy/quarry.toml`
(non-loopback host) wins — host:port + pinned `ca_cert` + `Authorization: Bearer`;
otherwise the **local daemon** on loopback is resolved from the daemon's live
`serve.port` + `serve.token` in its startup-database run dir
(`~/.punt-labs/quarry/data/<db>/`, `<db>` from `config.toml`'s `[default]
database`, else `default`), pinning the local CA and dialing `127.0.0.1`.
`QuarryClient` talks the REST API under `/v1/` (only `/health` at the root) with a
Bearer token and the pinned CA.

### Why

The Swift client and the Python CLI are two ports of one contract; mirroring the
CLI's resolution keeps them in step and gives remote support for free. Drift is
the failure mode: Quarry 2.0 moved endpoints under `/v1/` and added loopback
`serve.token` auth, which broke the app until this alignment (see the git
history for the v0.6.1 fix).

### Alternatives

1. **Read only the `mcp-proxy/quarry.toml` (v1-era behavior).** Rejected — it has
   no loopback token and no `/v1` knowledge; it broke wholesale against Quarry 2.0.
2. **Share quarry's Python client library.** Rejected — different language; a
   Swift port is required. The mitigation for drift is ADR-007's contract test.
3. **`QUARRY_URL`/`QUARRY_TOKEN` env tier** (quarry's tier 1). Deliberately not
   implemented: the app launches via `open`, which propagates no shell env, so an
   env tier would be dead, untestable code. Documented in `load()`.

---

## ADR-004: Put `QuarryClient` behind a protocol (the missing testability seam)

**Status:** Proposed — tracked by a bead. This is the single change that most
raises coverage.

### Decision

Introduce `QuarryClientProtocol` declaring the client surface (`health`, `search`,
`show`, `status`, `databases`, `documents`, `collections`). Models depend on the
**protocol**; `QuarryClient` (concrete) is injected with a defaulted initializer
and keeps an injectable `URLSession`/transport. Tests substitute a hand-written
fake (a call-recorder, per `../koch-trainer-swift/…/SilentAudioEngine.swift`).

### Why

`SearchViewModel(client: QuarryClient)` and `ResultDetail` currently take the
**concrete** class, so their network-dependent paths cannot be tested against a
fake — only with a real client + injected `URLSession`, or the static-func
workaround in `ResultDetail`. That is a large share of the un-covered ~48%.
Quarry itself made this a seam (DES-031 R5: "`QuarryClient` + injectable REST
transport"); `../koch-trainer-swift` proves the payoff — `AudioEngineProtocol`
with constructor injection at `ReceiveTrainingViewModel.swift:13-16`.

### Alternatives

1. **Keep the concrete client; stub with `URLProtocol`.** Partially works but is
   brittle, couples tests to HTTP wire details, and does not help pure model logic.
2. **Static functions on the type (today's `ResultDetail.loadContent`).**
   Rejected — see ADR-005; it is the anti-pattern of ADR-001.

---

## ADR-005: Move detail loading into a `ResultDetailViewModel`

**Status:** Proposed — tracked by a bead (depends on ADR-004).

### Decision

Extract `ResultDetail.loadContent` (the `client.show` call + syntax highlighting +
the excerpt fallback) out of the `View`'s `static func`/`.task(id:)` into a
`@MainActor @Observable ResultDetailViewModel` injected with `QuarryClientProtocol`.
The view renders the view-model's published state; the view-model owns the async
load.

### Why

Detail loading is the same view-lifecycle coupling as the connect bug (ADR-002),
one layer down: network work lives inside a view and is tested only through a
static workaround. A view-model makes the load fakeable and independent of the
detail panel's lifecycle.

### Alternatives

Keep `loadContent` static on the view. Rejected — it is why `ResultDetailTests`
must reach through a static, and it repeats the coupling ADR-002 removed.

---

## ADR-006: TLS everywhere with TOFU certificate pinning

**Status:** Accepted.

### Decision

Every Quarry connection — including loopback — is HTTPS, verified against a
**pinned self-signed CA** via `PinnedCASessionDelegate` (a `SecTrust` evaluation
with an explicit anchor, host-SAN match, and `serverAuth` EKU check). Loopback
pins `~/.punt-labs/quarry/tls/ca.crt`; remote pins the `quarry.toml` `ca_cert`.
System root trust is excluded.

### Why

Mirrors quarry's DES-020 (TLS everywhere, TOFU pinning). Quarry servers hold the
user's whole corpus and the API key; pinning the personal CA (not system roots)
is the correct trust model for personal infrastructure with no PKI.

### Alternatives

1. **Trust system roots.** Rejected — the cert is self-signed.
2. **Plain HTTP on loopback.** Rejected — the daemon serves TLS on loopback, and
   a "just localhost" exception is the split-security-model quarry deliberately
   avoids.

---

## ADR-007: Testability posture — protocol fakes, injected clocks, coverage target, real-app gate

**Status:** Accepted (target); path is the ADR-004/005 beads.

### Decision

Adopt the `../koch-trainer-swift` testing conventions:

- **Hand-written fakes** conforming to the service protocols (call-recorders that
  assert behavior), not mocking frameworks.
- **Inject the clock/delays** for any time-dependent logic (retry/backoff/debounce)
  so tests are synchronous and deterministic — no real waits.
- **`make coverage`** (already present) reports line coverage; adopt an
  *adjusted-coverage* convention that excludes enumerated purely-presentational
  views, and set a target (koch runs ~88% adjusted; ours is **52.1%** today).
  Raising it is gated on ADR-004/005, not on bolting tests onto the current shape.
- **The running app is the release gate.** For any change touching connection,
  runtime, or UI, a unit test or a backend harness verifies the *contract*, never
  the app's real `URLSession`/TLS/`@MainActor`/`MenuBarExtra` runtime flow. The
  app must be driven to Connected → search → detail (real UI or operator eyeball)
  before merge/release. See `CLAUDE.md` → "Verify Outputs, Not Just Gates". This
  rule exists because the v0.6.1 connect bug passed a harness and a skip-guarded
  live unit test but failed the actual app.

### Why

52.1% line coverage is not "SwiftUI is untestable" — it is the ADR-004/005
coupling gaps plus the absence of a client seam. Fixing the layering, not adding
UI tests, is what moves the number and prevents the class of bug that shipped in
v0.6.1.

### Alternatives

1. **Raise coverage by testing Views directly.** Rejected — tests the framework,
   not our logic; brittle. Extract logic to models (ADR-004/005) instead.
2. **Treat a passing harness/unit suite as sufficient verification.** Rejected —
   it shipped a broken app once already.

---

## ADR-008: Keep the Swift client in sync with quarry's wire contract

**Status:** Proposed — tracked by qmb-36v (depends on the Quarry 2.0 client fix).

### Decision

Two drift guards: (1) a **runtime `api_version` check** — read `/health`'s
`api_version`/`quarry_version`; on an unsupported API version show a clear
"update quarry-menubar" state instead of 404/401s; (2) a **build-time contract
test** against quarry's published OpenAPI spec (codegen `QuarryModels` from it, or
assert the `/v1` endpoints + shapes the app depends on).

### Why

The Swift port and quarry's Python `quarry/api` are parallel definitions. The
`/v1` + `serve.token` change broke the app silently because only runtime breakage
caught it. A contract guard turns the next quarry API change into a red build, not
a user-visible failure.

### Alternatives

Rely on manual re-verification each quarry release. Rejected — that is exactly
what failed here.
