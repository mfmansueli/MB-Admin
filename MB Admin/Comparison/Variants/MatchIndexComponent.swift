import Foundation

/// Uma parcela do índice de correspondência — o que a revisão mostra linha a linha ("a mesma foto
/// +55", "aro 16 × aro 18 −35").
nonisolated struct MatchIndexComponent: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case photo
        case title
        case description
        case attribute(VariantDimension)
        case brand
        case category
        case price
    }

    let kind: Kind
    let points: Int
    let text: String

    /// "+55", "−35", "0".
    var signedPoints: String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(-points)" }
        return "0"
    }
}
