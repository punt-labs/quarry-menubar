# How the App Finds Quarry

quarry-menubar is a client of Quarry's `quarryd` service. It does not start,
stop, or manage `quarryd`, and it does not need the `quarry` command on `PATH`
at run time. It resolves its connection the same way the `quarry` command-line
tool does (see [DESIGN.md](../DESIGN.md) ADR-003).

## Connection Resolution

1. **Remote.** If `~/.punt-labs/mcp-proxy/quarry.toml` names a host that is not
   loopback, the app uses that server. It takes the host and port from `url`,
   pins the certificate authority in `ca_cert`, and sends the stored token as
   `Authorization: Bearer <token>`. `quarry login` writes this file and
   `quarry logout` deletes it.
2. **Local.** Otherwise the app connects to `quarryd` on `127.0.0.1`. It reads
   the port from `serve.port` and the token from `serve.token` in the run
   directory of the daemon's startup database,
   `~/.punt-labs/quarry/data/<db>/`. `<db>` is the `[default] database` value
   in `~/.punt-labs/quarry/config.toml`, or `default` if it is not set. The app
   pins the local certificate authority at `~/.punt-labs/quarry/tls/ca.crt`.
   A `quarry.toml` that names a loopback host falls through to this path.

The app reports a distinct configuration error when `serve.port` is missing
(the daemon is not running), when `serve.port` or `serve.token` cannot be read
or is invalid, or when `config.toml` cannot be parsed.

Reveal in Finder is available only on a local connection, because the file
paths Quarry returns belong to the machine that runs `quarryd`.

## API Endpoints

Quarry serves its endpoints under `/v1/`; only `/health` is at the root. The
app uses these read-only endpoints:

| Endpoint | Used for |
|----------|----------|
| `GET /health` | Connection check |
| `GET /v1/status` | Database statistics |
| `GET /v1/databases` | Active database name |
| `GET /v1/collections` | Collection filter menu |
| `GET /v1/search?q=&limit=` | Search results |
| `GET /v1/show?document=&page=` | Full page text in the result view |
| `GET /v1/documents?collection=` | Source file path for Reveal in Finder |

## App Structure

```text
QuarryMenuBarApp / AppDelegate           # owns the app-lifetime ConnectionManager;
  -> ConnectionManager                   #   connects once at applicationDidFinishLaunching
       (owns the connect Task at app scope, not a view's .task, which MenuBarExtra cancels)
  -> ConnectionProfileLoader             # remote quarry.toml, else loopback serve.port/serve.token
  -> QuarryClient (HTTPS /v1 + Bearer auth + pinned CA)
  -> SearchViewModel (debounced search via QuarryClient)
  -> ContentPanel (renders by connection state; delegates connect/refresh to ConnectionManager)
```

Connection ownership lives at app scope, not in a view. See
[DESIGN.md](../DESIGN.md) ADR-002 for why and ADR-001 for the thin-views
principle it follows.

The app uses one third-party package, `HighlightSwift`, for syntax
highlighting themes. App state uses SwiftUI and the `@Observable` macro.
