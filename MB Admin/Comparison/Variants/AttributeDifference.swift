import Foundation

/// Um eixo em que dois anúncios descrevem versões diferentes — "aro 16 × aro 18".
nonisolated struct AttributeDifference: Equatable, Sendable {
    let dimension: VariantDimension
    /// O valor do anúncio de referência (o da loja A num par; o "daqui" num aviso de outra versão).
    let valueA: VariantValue
    let valueB: VariantValue

    var text: String { "\(valueA.display) × \(valueB.display)" }

    var reversed: AttributeDifference {
        AttributeDifference(dimension: dimension, valueA: valueB, valueB: valueA)
    }
}
