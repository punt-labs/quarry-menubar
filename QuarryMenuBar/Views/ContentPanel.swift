import HighlightSwift
import SwiftUI

/// Root content view for the menu bar panel.
///
/// Manages daemon lifecycle (start on appear, stop on disappear)
/// and routes to the appropriate view based on daemon state.
struct ContentPanel: View {

    // MARK: Internal

    let daemon: DaemonManager

    @Bindable var searchViewModel: SearchViewModel

    let databaseManager: DatabaseManager
    let onDatabaseSwitch: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusContent
                .animation(.easeInOut(duration: 0.15), value: daemon.state)
            Divider()
            footer
        }
        .preferredColorScheme(activeThemeIsDark ? .dark : .light)
        .task {
            daemon.start()
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

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Quarry")
                .font(.headline)
            DatabasePickerView(
                databaseManager: databaseManager,
                onSwitch: onDatabaseSwitch
            )
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
        switch daemon.state {
        case .stopped:
            statusLabel("Stopped", systemImage: "circle", iconStyle: .secondary)
        case .starting:
            statusLabel("Starting…", systemImage: "circle.dotted", iconStyle: .orange)
        case .running:
            statusLabel("Running", systemImage: "circle.fill", iconStyle: .green)
        case let .error(message):
            statusLabel(message, systemImage: "exclamationmark.triangle.fill", iconStyle: .red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch daemon.state {
        case .stopped:
            VStack(spacing: 12) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Backend Stopped")
                    .font(.headline)
                Text("The search backend is not running.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start") {
                    daemon.start()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case .starting:
            VStack(spacing: 8) {
                ProgressView("Starting Quarry…")
                Text("Launching the search backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.emptyStateTopPadding)
        case .running:
            SearchPanel(viewModel: searchViewModel)
        case let .error(message):
            ErrorStateView(message: message) {
                daemon.restart()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Quit") {
                daemon.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
