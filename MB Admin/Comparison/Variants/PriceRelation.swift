import Foundation

/// O preço inicial (sem desconto) de dois anúncios comparado — medida, não decisão. Um preço
/// diferente sozinho nunca separa dois anúncios com a mesma foto; ele pesa no índice, desempata
/// versões que dividem a mesma foto e, bem diferente num par 1:1, pede revisão (ver
/// `ComparisonResolver`).
nonisolated enum PriceRelation: Equatable, Sendable {
    case same
    /// Diferença até `MatchIndexParameters.closePriceTolerance`.
    case close
    case different
    /// Um dos dois sem preço.
    case unknown

    static func between(_ first: Double?, _ second: Double?) -> PriceRelation {
        guard let first, let second, first > 0, second > 0 else { return .unknown }
        let difference = abs(first - second)
        let larger = max(first, second)
        if difference <= max(MatchIndexParameters.samePriceAbsoluteTolerance, larger * MatchIndexParameters.samePriceTolerance) {
            return .same
        }
        return difference <= larger * MatchIndexParameters.closePriceTolerance ? .close : .different
    }

    /// Um preço passa de `MatchIndexParameters.farPriceRatio` vezes o outro.
    static func areFarApart(_ first: Double?, _ second: Double?) -> Bool {
        guard let first, let second, first > 0, second > 0 else { return false }
        return max(first, second) / min(first, second) > MatchIndexParameters.farPriceRatio
    }

    /// "R$ 100,00" — sempre em português, como o resto do app.
    static func format(_ price: Double) -> String {
        price.formatted(.currency(code: "BRL").presentation(.narrow).locale(Locale(identifier: "pt_BR")))
    }
}
