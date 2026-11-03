import Foundation

/// O índice de correspondência de um par: de 0 a 100, a soma (limitada) das parcelas de cada
/// evidência — foto, título base, descrição, atributos de variante, marca, categoria e preço inicial.
/// Pesos em `MatchIndexParameters`. **Não é probabilidade**: é uma pontuação explicável, que a tela
/// mostra com todas as parcelas; o estado do par sai das regras do `ComparisonResolver`.
nonisolated struct MatchIndex: Equatable, Sendable {
    nonisolated enum Level: Sendable {
        case high
        case medium
        case low
    }

    let score: Int
    let components: [MatchIndexComponent]

    init(components: [MatchIndexComponent]) {
        self.components = components
        score = min(100, max(0, components.reduce(0) { $0 + $1.points }))
    }

    static let empty = MatchIndex(components: [])

    var level: Level {
        if score >= MatchIndexParameters.highIndex { return .high }
        if score >= MatchIndexParameters.mediumIndex { return .medium }
        return .low
    }

    var levelText: String {
        switch level {
        case .high: "alto"
        case .medium: "médio"
        case .low: "baixo"
        }
    }
}
