import SwiftUI

// MARK: - ErrorStateView

struct ErrorStateView: View {

    // MARK: Internal

    let title: String
    let message: String
    let hint: String?
    let retryLabel: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.red)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(retryLabel) {
                onRetry()
            }
            .buttonStyle(.borderedProminent)

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Self.emptyStateTopPadding)
    }

    // MARK: Private

    private static let emptyStateTopPadding: CGFloat = 40
}
