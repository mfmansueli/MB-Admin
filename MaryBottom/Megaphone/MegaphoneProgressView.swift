import SwiftUI

/// Resumo do andamento do megafone.
struct MegaphoneProgressView: View {
    let runner: MegaphoneRunner

    private var statusText: MegaphoneStatusText {
        MegaphoneStatusText(
            phase: runner.phase,
            itemsCount: runner.items.count,
            processedCount: runner.processedCount,
            totalSucceeded: runner.totalSucceeded,
            totalFailed: runner.totalFailed,
            round: runner.round
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusText.headline)
                .font(.headline.weight(.medium))

            if let progress = statusText.progress {
                ProgressView(value: progress)
            }

            if !runner.items.isEmpty {
                Text(totals)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: String {
        "\(runner.totalSucceeded) megafones · \(runner.totalFailed) com erro · \(runner.items.count) produtos"
    }
}
