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
        .task {
            daemon.start()
        }
    }

    // MARK: Private

    private static let emptyStateTopPadding: CGFloat = 40

    /// Curated subset of HighlightTheme for the picker.
    private static let themeChoices: [(theme: HighlightTheme, label: String)] = [
        (.xcode, "Xcode"),
        (.github, "GitHub"),
        (.atomOne, "Atom One"),
        (.solarized, "Solarized"),
        (.tokyoNight, "Tokyo Night"),
        (.standard, "Standard")
    ]

    @AppStorage("syntaxTheme") private var themeName: String = "xcode"

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
            ForEach(Self.themeChoices, id: \.theme) { choice in
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
