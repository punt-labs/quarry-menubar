import SwiftUI

/// Root content view for the menu bar panel.
///
/// Manages daemon lifecycle (start on appear, stop on disappear)
/// and routes to the appropriate view based on daemon state.
struct ContentPanel: View {

    // MARK: Internal

    let daemon: DaemonManager

    @Bindable var searchViewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusContent
            Divider()
            footer
        }
        .task {
            daemon.start()
        }
    }

    // MARK: Private

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Quarry")
                .font(.headline)
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch daemon.state {
        case .stopped:
            Label("Stopped", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "circle.dotted")
                .font(.caption)
                .foregroundStyle(.orange)
        case .running:
            Label("Running", systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch daemon.state {
        case .stopped,
             .starting:
            ContentUnavailableView(
                "Starting Quarry…",
                systemImage: "gear",
                description: Text("Launching the search backend.")
            )
        case .running:
            SearchPanel(viewModel: searchViewModel)
        case let .error(message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "Backend Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                Button("Restart") {
                    daemon.restart()
                }
                .buttonStyle(.borderedProminent)
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
}
