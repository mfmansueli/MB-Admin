import Foundation

/// Um eixo em que versões do mesmo produto costumam variar — e que o texto do anúncio (título,
/// descrição, o campo de tamanho do template) costuma dizer. Muitas lojas usam a **mesma foto** pra
/// todas as versões (aro 16 e aro 18, banho de ouro e de ródio), então é aqui que a comparação
/// separa "o mesmo produto" de "outra versão dele".
nonisolated enum VariantDimension: String, CaseIterable, Hashable, Sendable {
    /// Aro do anel, numeração, tamanho de roupa (P/M/G).
    case size
    /// Banho/acabamento do metal: ouro, ouro rosé, ródio, ródio negro, prateado, prata.
    case finish
    /// Cor da pedra (ou da peça): zircônia branca, rosa, azul…
    case stoneColor
    /// Medida com unidade: comprimento da corrente (45 cm), diâmetro da argola (50 mm).
    case measure

    /// O nome do eixo na tela ("tamanho", "banho"…).
    var label: String {
        switch self {
        case .size: "tamanho"
        case .finish: "banho"
        case .stoneColor: "cor"
        case .measure: "medida"
        }
    }

    /// Dois valores **decisivos** deste eixo descrevem versões diferentes? No banho, tons da mesma
    /// família de cor (ródio, prata, prateado, ouro branco) não contam como conflito — a mesma peça
    /// em prata 925 com banho de ródio é anunciada das duas formas.
    func conflicts(_ first: VariantValue, _ second: VariantValue) -> Bool {
        guard first != second else { return false }
        switch self {
        case .finish:
            return Self.finishTone(first.canonical) != Self.finishTone(second.canonical)
        case .size, .stoneColor, .measure:
            return true
        }
    }

    private static func finishTone(_ canonical: String) -> String {
        switch canonical {
        case "ouro": "dourado"
        case "ouro rose": "rose"
        case "rodio negro": "negro"
        default: "prateado"
        }
    }
}
