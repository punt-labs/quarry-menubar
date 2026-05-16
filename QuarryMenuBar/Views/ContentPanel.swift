import HighlightSwift
import SwiftUI

struct ContentPanel: View {

    // MARK: Internal

    let connectionManager: ConnectionManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .animation(.easeInOut(duration: 0.15), value: connectionManager.state)
            Divider()
            footer
        }
        .preferredColorScheme(activeThemeIsDark ? .dark : .light)
        .task {
            if case .idle = connectionManager.state {
                await connectionManager.refresh()
            }
        }
    }

    static func unavailableHint(for mode: ConnectionMode?) -> String {
        switch mode {
        case .remote:
            "Check that the remote Quarry server is reachable and that its pinned CA and token are still valid."
        case .local,
             .none:
            "Run `quarry install` to set up local Quarry, or run `quarry login <host> --api-key <token>` to point Quarry at a remote server. You can also set `QUARRY_API_KEY` before running `quarry login <host>`."
        }
    }

    static func configurationHint(for origin: ConnectionOrigin?) -> String {
        switch origin {
        case .proxyConfig:
            "Fix `~/.punt-labs/mcp-proxy/quarry.toml`, rerun `quarry login <host> --api-key <token>` (or set `QUARRY_API_KEY` first), or run `quarry logout` if you want the app to return to local Quarry."
        case .localDefault,
             .none:
            "Run `quarry install` to create the local TLS certificates and daemon, or run `quarry login <host> --api-key <token>` to use a remote server. You can also set `QUARRY_API_KEY` before running `quarry login <host>`."
        }
    }

    // MARK: Private

    /// A curated theme entry for the picker.
    private struct ThemeChoice: Identifiable {
        let theme: HighlightTheme
        let label: String
        let isDark: Bool

        var id: HighlightTheme {
            theme
        }
    }

    private static let emptyStateTopPadding: CGFloat = 40

    /// Curated subset of HighlightTheme for the picker.
    /// `isDark` determines the panel's color scheme and which theme variant to use.
    private static let themeChoices: [ThemeChoice] = [
        ThemeChoice(theme: .xcode, label: "Xcode", isDark: false),
        ThemeChoice(theme: .github, label: "GitHub", isDark: false),
        ThemeChoice(theme: .atomOne, label: "Atom One", isDark: true),
        ThemeChoice(theme: .solarized, label: "Solarized", isDark: true),
        ThemeChoice(theme: .tokyoNight, label: "Tokyo Night", isDark: true),
        ThemeChoice(theme: .standard, label: "Standard", isDark: false)
    ]

    @AppStorage("syntaxTheme") private var themeName: String = "xcode"

    private var activeThemeIsDark: Bool {
        Self.themeChoices.first {
            $0.theme.rawValue.lowercased() == themeName.lowercased()
        }?.isDark ?? false
    }

    private var unavailableHint: String {
        Self.unavailableHint(for: connectionManager.profile?.mode)
    }

    private var configurationHint: String {
        Self.configurationHint(
            for: connectionManager.profile?.origin ?? connectionManager.failureOrigin
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Quarry")
                .font(.headline)
            if let profile = connectionManager.profile {
                pillLabel(
                    profile.displayName,
                    systemImage: profile.mode == .local ? "desktopcomputer" : "network"
                )
            }
            if let databaseName = connectionManager.activeDatabaseName {
                pillLabel(databaseName, systemImage: "internaldrive")
            }
            Spacer()
            themeMenu
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var themeMenu: some View {
        Menu {
            ForEach(Self.themeChoices) { choice in
                Button {
                    themeName = choice.theme.rawValue.lowercased()
                } label: {
                    HStack {
                        Text(choice.label)
                        if themeName.lowercased() == choice.theme.rawValue.lowercased() {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "paintbrush")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch connectionManager.state {
        case .idle,
             .connecting:
            statusLabel("Connecting…", systemImage: "circle.dotted", iconStyle: .orange)
        case .connected:
            statusLabel("Connected", systemImage: "circle.fill", iconStyle: .green)
        case .unavailable:
            statusLabel("Unavailable", systemImage: "exclamationmark.triangle.fill", iconStyle: .red)
        case .misconfigured:
            statusLabel("Config Error", systemImage: "wrench.and.screwdriver.fill", iconStyle: .orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch connectionManager.state {
        case .idle,
             .connecting:
            VStack(spacing: 8) {
                ProgressView("Connecting to Quarry…")
                Text("Resolving the active Quarry connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case .connected:
            if let searchViewModel = connectionManager.searchViewModel {
                SearchPanel(
                    viewModel: searchViewModel,
                    allowsFinderReveal: connectionManager.allowsLocalFileAccess
                )
            } else {
                ProgressView("Preparing search…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case let .unavailable(message):
            ErrorStateView(
                title: "Quarry Unavailable",
                message: message,
                hint: unavailableHint,
                retryLabel: "Retry"
            ) {
                Task { await connectionManager.refresh() }
            }
        case let .misconfigured(message):
            ErrorStateView(
                title: "Quarry Configuration",
                message: message,
                hint: configurationHint,
                retryLabel: "Reload Config"
            ) {
                Task { await connectionManager.refresh() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                Task { await connectionManager.refresh() }
            }
            .buttonStyle(.plain)
            .disabled(connectionManager.state == .connecting)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func pillLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: Capsule())
    }

    private func statusLabel(
        _ title: String,
        systemImage: String,
        iconStyle: some ShapeStyle
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(iconStyle)
            Text(title)
                .foregroundStyle(.primary)
        }
        .font(.footnote)
    }

}
