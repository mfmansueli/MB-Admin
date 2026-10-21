import Foundation

/// Qual parte do resultado da comparação a tela mostra — o menu de filtro da barra de cima.
nonisolated enum ComparisonResultFilter: Hashable, CaseIterable, Sendable {
    case all
    case matches
    /// Só em conta A — ou seja, os que faltam na conta B.
    case onlyInA
    /// Só em conta B — os que faltam na conta A.
    case onlyInB

    func label(result: AccountComparisonResult, accountAName: String, accountBName: String) -> String {
        switch self {
        case .all:
            "todos (\(result.matches.count + result.onlyInA.count + result.onlyInB.count))"
        case .matches:
            "em comum (\(result.matches.count))"
        case .onlyInA:
            "não encontrados em \(accountBName) (\(result.onlyInA.count))"
        case .onlyInB:
            "não encontrados em \(accountAName) (\(result.onlyInB.count))"
        }
    }

    func includes(_ section: Self) -> Bool {
        self == .all || self == section
    }
}
