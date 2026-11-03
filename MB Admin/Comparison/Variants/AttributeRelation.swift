import Foundation

/// Como um eixo de variante se compara entre dois anúncios.
nonisolated enum AttributeRelation: Equatable, Sendable {
    /// Os dois dizem o mesmo valor.
    case agrees
    /// Valores diferentes, mas da mesma família (ródio × prata) — nem a favor nem contra.
    case compatible
    /// Valores que descrevem versões diferentes (aro 16 × aro 18, ouro × ródio).
    case conflicts
    /// Um dos dois (ou os dois) não diz, ou diz mais de um valor.
    case unknown

    static func between(_ first: AttributeReading?, _ second: AttributeReading?, dimension: VariantDimension) -> AttributeRelation {
        guard let valueA = first?.decisiveValue, let valueB = second?.decisiveValue else { return .unknown }
        if valueA == valueB { return .agrees }
        return dimension.conflicts(valueA, valueB) ? .conflicts : .compatible
    }
}
