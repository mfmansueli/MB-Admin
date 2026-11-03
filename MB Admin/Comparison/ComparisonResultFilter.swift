import Foundation

/// Qual parte do resultado da comparação a tela mostra — o menu de filtro da barra de cima.
nonisolated enum ComparisonResultFilter: Hashable, CaseIterable, Sendable {
    case all
    /// Correspondência forte ou confirmada.
    case matches
    case review
    /// Produtos com várias versões (a mesma foto em vários anúncios) e onde cada versão está.
    case variants
    /// O mesmo produto cadastrado mais de uma vez na mesma loja (em qualquer das duas).
    case duplicates
    /// Produtos de A sem nenhum indício em B.
    case missingInB
    /// Produtos de B sem nenhum indício em A.
    case missingInA
    case unverified
    case rejected

    func label(result: AccountComparisonResult, accountAName: String, accountBName: String) -> String {
        switch self {
        case .all:
            // Conta anúncios/pares — famílias e repetidos são agrupamentos deles, não somam.
            let total = result.matches.count + result.reviews.count + result.possiblyMissingInB.count
                + result.possiblyMissingInA.count + result.unverifiedCount + result.rejected.count
            return "todos (\(total))"
        case .matches: return "mesmo produto (\(result.matches.count))"
        case .review: return "precisa revisar (\(result.reviews.count))"
        case .variants: return "com variantes (\(result.families.count))"
        case .duplicates: return "repetidos na mesma loja (\(result.duplicateCount))"
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
