import Foundation

/// Qual parte do resultado da comparação a tela mostra — o menu de filtro da barra de cima.
nonisolated enum ComparisonResultFilter: Hashable, CaseIterable, Sendable {
    case all
    /// Correspondência forte ou confirmada.
    case matches
    case review
    /// Produtos de A sem nenhum indício em B.
    case missingInB
    /// Produtos de B sem nenhum indício em A.
    case missingInA
    case unverified
    case rejected

    func label(result: AccountComparisonResult, accountAName: String, accountBName: String) -> String {
        switch self {
        case .all:
            let total = result.matches.count + result.reviews.count + result.possiblyMissingInB.count
                + result.possiblyMissingInA.count + result.unverifiedCount + result.rejected.count
            return "todos (\(total))"
        case .matches: return "mesmo produto (\(result.matches.count))"
        case .review: return "precisa revisar (\(result.reviews.count))"
        case .missingInB: return "possivelmente ausentes em \(accountBName) (\(result.possiblyMissingInB.count))"
        case .missingInA: return "possivelmente ausentes em \(accountAName) (\(result.possiblyMissingInA.count))"
        case .unverified: return "não verificados (\(result.unverifiedCount))"
        case .rejected: return "marcados como diferentes (\(result.rejected.count))"
        }
    }

    func includes(_ section: Self) -> Bool {
        self == .all || self == section
    }
}
