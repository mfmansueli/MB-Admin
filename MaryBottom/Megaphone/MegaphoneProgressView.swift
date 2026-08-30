import SwiftUI

/// Resumo do andamento do megafone.
struct MegaphoneProgressView: View {
    let runner: MegaphoneRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.subheadline.weight(.medium))

            if let progress {
                ProgressView(value: progress)
            }

            if !runner.items.isEmpty {
                Text(totals)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        switch runner.phase {
        case .idle:
            "pronto para megafonar."
        case .loadingProducts(let loaded, let total):
            total > 0 ? "buscando seus produtos… \(loaded) de \(total)" : "buscando seus produtos…"
        case .megaphoning(let round, let rounds):
            "\(roundLabel(round, of: rounds))megafonando \(runner.processedCount + 1) de \(runner.items.count)…"
        case .paused(let round, let rounds, let reason):
            roundLabel(round, of: rounds) + pausedText(reason)
        case .finished:
            "fim: \(runner.totalSucceeded) megafones, \(runner.totalFailed) com erro."
        case .cancelled:
            "interrompido na rodada \(runner.round), com \(runner.totalSucceeded) megafones."
        case .failed(let message):
            message
        }
    }

    private var totals: String {
        "\(runner.totalSucceeded) megafones · \(runner.totalFailed) com erro · \(runner.items.count) produtos"
    }

    /// Fração concluída. Com repetição infinita não existe fim, então mostramos só a rodada atual.
    private var progress: Double? {
        switch runner.phase {
        case .loadingProducts(let loaded, let total):
            return total > 0 ? Double(loaded) / Double(total) : nil
        case .megaphoning(let round, let rounds), .paused(let round, let rounds, _):
            guard !runner.items.isEmpty else { return nil }
            if rounds.isUnlimited {
                return Double(runner.processedCount) / Double(runner.items.count)
            }
            let done = Double((round - 1) * runner.items.count + runner.processedCount)
            return done / Double(runner.items.count * rounds.rawValue)
        case .idle, .finished, .cancelled, .failed:
            return nil
        }
    }

    private func pausedText(_ reason: MegaphonePauseReason) -> String {
        switch reason {
        case .user: "pausado — toque em continuar quando quiser."
        case .background: "pausado em segundo plano — volta sozinho quando você reabrir o app."
        }
    }

    private func roundLabel(_ round: Int, of rounds: MegaphoneRounds) -> String {
        if rounds.isUnlimited { return "rodada \(round) · " }
        if rounds.rawValue == 1 { return "" }
        return "rodada \(round) de \(rounds.rawValue) · "
    }
}
