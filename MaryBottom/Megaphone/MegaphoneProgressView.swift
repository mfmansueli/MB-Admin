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
            // Sem nada acontecendo ainda, o próprio botão "megafonar" já diz isso — a linha some,
            // em vez de repetir com "pronto para megafonar.".
            if runner.phase != .idle {
                Text(statusText.headline)
                    .font(.headline.weight(.medium))
            }

            if let progress = statusText.progress {
                ProgressView(value: progress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
