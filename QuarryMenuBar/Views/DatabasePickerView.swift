import SwiftUI

/// Compact database picker for the panel header.
///
/// Shows a borderless menu button with the current database name and a chevron.
/// The menu lists all discovered databases with doc count and size metadata.
struct DatabasePickerView: View {

    let databaseManager: DatabaseManager
    let onSwitch: (String) -> Void

    var body: some View {
        Menu {
            if databaseManager.isDiscovering {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else if databaseManager.discoveryTimedOut, databaseManager.availableDatabases.isEmpty {
                Text("Discovery timed out")
                    .foregroundStyle(.secondary)
            } else if databaseManager.availableDatabases.isEmpty {
                Text("No databases found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(databaseManager.availableDatabases) { db in
                    Button {
                        onSwitch(db.name)
                    } label: {
                        HStack {
                            Text(db.name)
                            Spacer()
                            Text("\(db.documentCount) docs, \(db.sizeDescription)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(db.name == databaseManager.currentDatabase)
                }
            }

            Divider()

            Button {
                Task { await databaseManager.loadDatabases() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 3) {
                Text(databaseManager.currentDatabase)
                    .font(.subheadline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .task {
            await databaseManager.loadDatabases()
        }
    }
}
