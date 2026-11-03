import Foundation

/// O que o texto de um anúncio diz sobre um eixo de variante.
nonisolated enum AttributeReading: Equatable, Sendable {
    /// Um valor só — decide (pode concordar ou conflitar com o outro anúncio).
    case decisive(VariantValue)
    /// Mais de um valor ("aro 14 ao 20", "zircônia branca e rosa") — não decide nada, nem a favor
    /// nem contra.
    case ambiguous([VariantValue])

    var decisiveValue: VariantValue? {
        if case .decisive(let value) = self { return value }
        return nil
    }

    var display: String {
        switch self {
        case .decisive(let value): value.display
        case .ambiguous(let values): values.map(\.display).joined(separator: ", ")
        }
    }

    /// `nil` sem valor nenhum; decisivo com um; ambíguo com mais de um (na ordem em que apareceram).
    static func from(_ values: [VariantValue]) -> AttributeReading? {
        var unique: [VariantValue] = []
        for value in values where !unique.contains(value) {
            unique.append(value)
        }
        switch unique.count {
        case 0: return nil
        case 1: return .decisive(unique[0])
        default: return .ambiguous(unique)
        }
    }
}
