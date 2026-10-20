import Foundation

/// Resultado de comparar o catálogo de duas contas: os pares que a comparação achou parecidos o
/// bastante, e o que sobrou sem par de cada lado.
nonisolated struct AccountComparisonResult: Equatable, Sendable {
    /// Único por comparação (gerado na hora, não vem do Enjoei) — deixa `ComparisonResultView` se
    /// identificar por `.id(result.id)` na tela, pra trocar de conta (ou comparar o mesmo par de
    /// novo) sempre nascer com busca/filtro/seleção zerados, em vez de arrastar o que sobrou
    /// marcado da comparação anterior.
    let id = UUID()
    let matches: [ProductMatch]
    let onlyInA: [EnjoeiProduct]
    let onlyInB: [EnjoeiProduct]
}
