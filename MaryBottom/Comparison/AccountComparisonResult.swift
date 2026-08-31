import Foundation

/// Resultado de comparar o catálogo de duas contas: os pares que a comparação achou parecidos o
/// bastante, e o que sobrou sem par de cada lado.
nonisolated struct AccountComparisonResult: Equatable, Sendable {
    let matches: [ProductMatch]
    let onlyInA: [EnjoeiProduct]
    let onlyInB: [EnjoeiProduct]
}
