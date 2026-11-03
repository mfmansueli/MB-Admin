import Foundation

/// Uma linha da tabela "lado a lado" da revisão: o mesmo atributo nos dois anúncios.
nonisolated struct MatchAttributeRow: Equatable, Sendable {
    let label: String
    let valueA: String?
    let valueB: String?
    let relation: AttributeRelation

    /// Os eixos de variante que algum dos dois diz, a marca e o preço inicial.
    static func rows(_ first: ListingAttributes, _ second: ListingAttributes) -> [MatchAttributeRow] {
        var rows: [MatchAttributeRow] = []
        for dimension in VariantDimension.allCases {
            let readingA = first.reading(dimension)
            let readingB = second.reading(dimension)
            guard readingA != nil || readingB != nil else { continue }
            rows.append(MatchAttributeRow(
                label: dimension.label,
                valueA: readingA?.display,
                valueB: readingB?.display,
                relation: AttributeRelation.between(readingA, readingB, dimension: dimension)
            ))
        }
        if first.brand != nil || second.brand != nil {
            let relation: AttributeRelation = if let brandA = first.brand, let brandB = second.brand {
                brandA == brandB ? .agrees : .conflicts
            } else {
                .unknown
            }
            rows.append(MatchAttributeRow(label: "marca", valueA: first.brandDisplay, valueB: second.brandDisplay, relation: relation))
        }
        if first.price != nil || second.price != nil {
            let relation: AttributeRelation = switch PriceRelation.between(first.price, second.price) {
            case .same: .agrees
            case .close: .compatible
            case .different: .conflicts
            case .unknown: .unknown
            }
            rows.append(MatchAttributeRow(
                label: "preço inicial",
                valueA: first.price.map(PriceRelation.format),
                valueB: second.price.map(PriceRelation.format),
                relation: relation
            ))
        }
        return rows
    }
}
