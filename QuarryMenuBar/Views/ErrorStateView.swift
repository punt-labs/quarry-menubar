import SwiftUI

// MARK: - ErrorStateView

/// Displays daemon errors with actionable guidance based on error type.
struct ErrorStateView: View {

    // MARK: Internal

    let message: String
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: errorIcon)
                .font(.system(size: 40))
                .foregroundStyle(errorColor)

            Text(errorTitle)
                .font(.headline)

            Text(errorDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if showRestart {
                Button("Restart Backend") {
                    onRestart()
                }
                .buttonStyle(.borderedProminent)
            }

            if let hint = installHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: Private

    private var errorCategory: ErrorCategory {
        let lower = message.lowercased()
        if lower.contains("not found") || lower.contains("no such file") {
            return .notInstalled
        } else if lower.contains("exited with code") {
            return .crashed
        } else {
            return .unknown
        }
    }

    private var errorIcon: String {
        switch errorCategory {
        case .notInstalled:
            "exclamationmark.questionmark"
        case .crashed:
            "bolt.trianglebadge.exclamationmark"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    private var errorColor: Color {
        switch errorCategory {
        case .notInstalled:
            .orange
        case .crashed,
             .unknown:
            .red
        }
    }

    private var errorTitle: String {
        switch errorCategory {
        case .notInstalled:
            "Quarry Not Found"
        case .crashed:
            "Backend Crashed"
        case .unknown:
            "Backend Error"
        }
    }

    private var errorDescription: String {
        switch errorCategory {
        case .notInstalled:
            "The quarry command was not found. Make sure quarry is installed and available in your PATH."
        case .crashed:
            message
        case .unknown:
            message
        }
    }

    private var showRestart: Bool {
        switch errorCategory {
        case .notInstalled:
            false
        case .crashed,
             .unknown:
            true
        }
    }

    private var installHint: String? {
        switch errorCategory {
        case .notInstalled:
            "Install with: pip install quarry  or  uv pip install quarry"
        case .crashed,
             .unknown:
            nil
        }
    }
}

// MARK: - ErrorCategory

private enum ErrorCategory {
    case notInstalled
    case crashed
    case unknown
}
