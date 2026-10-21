import Foundation

/// Formata o andamento do megafone em texto, a partir dos valores simples do `MegaphoneRunner`.
///
/// Extraído pra fora da view porque o texto compacto de cada row da lista de contas precisa do
/// mesmo cálculo que a tela de detalhe já fazia — sem duplicar o switch em dois lugares.
nonisolated struct MegaphoneStatusText: Equatable, Sendable {
    let headline: String
    let progress: Double?
    /// Só a contagem do produto da vez ("12 de 340") — o número grande do painel de andamento.
    /// `nil` fora de `.megaphoning`/`.paused`, onde não existe "produto da vez".
    let count: String?
    /// "rodada 2 de 5" (ou "rodada 3", no infinito) — `nil` numa rodada única, mesmo critério de
    /// `headline`, que também não menciona rodada nesse caso.
    let roundLabel: String?
    /// Linha curta da row da conta na lista ("rodada 2 de 5 · 12 de 340") — cabe numa linha só no
    /// iPhone, ao contrário de `headline`. Fora de megafonando/pausado, cai no próprio `headline`.
    let compactLine: String

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
        headline = switch phase {
        case .idle:
            "pronto para megafonar."
        case .waitingInQueue:
            "esperando a vez pra megafonar…"
        case .loadingProducts(let loaded, let total):
            total > 0 ? "buscando seus produtos… \(loaded) de \(total)" : "buscando seus produtos…"
        case .checkingExposure(let checked, let total):
            "conferindo quais pedem desconto… \(checked) de \(total)"
        case .megaphoning(let round, let rounds):
            "\(Self.roundLabel(round, of: rounds))megafonando \(processedCount + 1) de \(itemsCount)…"
        case .paused(let round, let rounds, let reason):
            Self.roundLabel(round, of: rounds) + Self.pausedText(reason)
        case .finished:
            "fim: \(totalSucceeded) megafones, \(totalFailed) com erro."
        case .cancelled:
            "interrompido na rodada \(round), com \(totalSucceeded) megafones."
        case .failed(let message):
            message
        }
        progress = Self.makeProgress(phase: phase, itemsCount: itemsCount, processedCount: processedCount)
        (count, roundLabel) = Self.makeCountAndRound(phase: phase, itemsCount: itemsCount, processedCount: processedCount)
        compactLine = Self.makeCompactLine(phase: phase, headline: headline, count: count, roundLabel: roundLabel)
    }

    private static func makeCompactLine(phase: MegaphonePhase, headline: String, count: String?, roundLabel: String?) -> String {
        switch phase {
        case .megaphoning: [roundLabel, count].compactMap { $0 }.joined(separator: " · ")
        case .paused: ["pausado", roundLabel, count].compactMap { $0 }.joined(separator: " · ")
        case .idle, .waitingInQueue, .loadingProducts, .checkingExposure, .finished, .cancelled, .failed: headline
        }
    }

    /// `count`/`roundLabel` — só existem com um produto da vez (megafonando ou pausado).
    private static func makeCountAndRound(
        phase: MegaphonePhase,
        itemsCount: Int,
        processedCount: Int
    ) -> (count: String?, roundLabel: String?) {
        switch phase {
        case .megaphoning(let round, let rounds), .paused(let round, let rounds, _):
            ("\(processedCount + 1) de \(itemsCount)", roundName(round, of: rounds))
        case .idle, .waitingInQueue, .loadingProducts, .checkingExposure, .finished, .cancelled, .failed:
            (nil, nil)
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
        case .idle, .waitingInQueue, .finished, .cancelled, .failed:
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
        roundName(round, of: rounds).map { "\($0) · " } ?? ""
    }

    private static func roundName(_ round: Int, of rounds: MegaphoneRounds) -> String? {
        if rounds.isUnlimited { return "rodada \(round)" }
        if rounds.rawValue == 1 { return nil }
        return "rodada \(round) de \(rounds.rawValue)"
    }
}
