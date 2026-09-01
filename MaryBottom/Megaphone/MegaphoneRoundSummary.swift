import Foundation

/// Resumo de uma rodada de megafone já concluída, guardado por conta para a lista mostrar algo
/// mesmo quando o megafone daquele usuário não está rodando no momento.
nonisolated struct MegaphoneRoundSummary: Equatable, Sendable, Codable {
    let succeeded: Int
    let failed: Int
    let finishedAt: Date

    /// `now` como parâmetro (em vez de `Date.now` direto) para o teste ser determinístico.
    func summaryText(now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: finishedAt, relativeTo: now)
        return "\(succeeded) sucesso, \(failed) falha, \(relative)"
    }
}
