import Foundation

/// Formata o andamento do megafone em texto, a partir dos valores simples do `MegaphoneRunner`.
///
/// Extraído pra fora da view porque o texto compacto de cada row da lista de contas precisa do
/// mesmo cálculo que a tela de detalhe já fazia — sem duplicar o switch em dois lugares.
nonisolated struct MegaphoneStatusText: Equatable, Sendable {
    let headline: String
    let progress: Double?

    /// - Parameter round: rodada em andamento guardada pelo runner — necessária à parte porque
    ///   `.cancelled` não carrega rodada no próprio `MegaphonePhase`.
    init(
        phase: MegaphonePhase,
        itemsCount: Int,
        processedCount: Int,
        totalSucceeded: Int,
        totalFailed: Int,
        round: Int
    ) {
        headline = Self.makeHeadline(
            phase: phase,
            itemsCount: itemsCount,
            processedCount: processedCount,
            totalSucceeded: totalSucceeded,
            totalFailed: totalFailed,
            round: round
        )
        progress = Self.makeProgress(phase: phase, itemsCount: itemsCount, processedCount: processedCount)
    }

    private static func makeHeadline(
        phase: MegaphonePhase,
        itemsCount: Int,
        processedCount: Int,
        totalSucceeded: Int,
        totalFailed: Int,
        round: Int
    ) -> String {
        switch phase {
        case .idle:
            "pronto para megafonar."
        case .loadingProducts(let loaded, let total):
            total > 0 ? "buscando seus produtos… \(loaded) de \(total)" : "buscando seus produtos…"
        case .checkingExposure(let checked, let total):
            "conferindo quais pedem desconto… \(checked) de \(total)"
        case .megaphoning(let round, let rounds):
            "\(roundLabel(round, of: rounds))megafonando \(processedCount + 1) de \(itemsCount)…"
        case .paused(let round, let rounds, let reason):
            roundLabel(round, of: rounds) + pausedText(reason)
        case .finished:
            "fim: \(totalSucceeded) megafones, \(totalFailed) com erro."
        case .cancelled:
            "interrompido na rodada \(round), com \(totalSucceeded) megafones."
        case .failed(let message):
            message
        }
    }

    /// Fração concluída. Com repetição infinita não existe fim, então mostramos só a rodada atual.
    private static func makeProgress(phase: MegaphonePhase, itemsCount: Int, processedCount: Int) -> Double? {
        switch phase {
        case .loadingProducts(let loaded, let total):
            return total > 0 ? Double(loaded) / Double(total) : nil
        case .checkingExposure(let checked, let total):
            return total > 0 ? Double(checked) / Double(total) : nil
        case .megaphoning(let round, let rounds), .paused(let round, let rounds, _):
            guard itemsCount > 0 else { return nil }
            if rounds.isUnlimited {
                return Double(processedCount) / Double(itemsCount)
            }
            let done = Double((round - 1) * itemsCount + processedCount)
            return done / Double(itemsCount * rounds.rawValue)
        case .idle, .finished, .cancelled, .failed:
            return nil
        }
    }

    private static func pausedText(_ reason: MegaphonePauseReason) -> String {
        switch reason {
        case .user: "pausado — toque em continuar quando quiser."
        case .background: "pausado em segundo plano — volta sozinho quando você reabrir o app."
        }
    }

    private static func roundLabel(_ round: Int, of rounds: MegaphoneRounds) -> String {
        if rounds.isUnlimited { return "rodada \(round) · " }
        if rounds.rawValue == 1 { return "" }
        return "rodada \(round) de \(rounds.rawValue) · "
    }
}
