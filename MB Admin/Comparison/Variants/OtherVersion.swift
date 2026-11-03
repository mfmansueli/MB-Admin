import Foundation

/// Outra versão de um produto na outra loja: um anúncio com a mesma foto que descreve outra versão
/// (aro, banho, cor ou medida diferente) — o "possivelmente ausente" que não está lá **nesta**
/// versão, mas está em outra.
nonisolated struct OtherVersion: Equatable, Sendable {
    let product: EnjoeiProduct
    /// O que muda, do anúncio daqui (`valueA`) pro da outra loja (`valueB`).
    let differences: [AttributeDifference]

    /// "aro 18 · ródio" — como a outra versão se descreve.
    var label: String { differences.map(\.valueB.display).joined(separator: " · ") }

    /// A linha que a tela mostra: "loja B tem outra versão: aro 18 (aqui: aro 16)", ou "loja B tem 3
    /// outras versões: aro 16, aro 20, ouro".
    static func summary(_ versions: [OtherVersion], storeName: String) -> String? {
        guard let first = versions.first else { return nil }
        if versions.count == 1 {
            let here = first.differences.map(\.valueA.display).joined(separator: " · ")
            return "\(storeName) tem outra versão: \(first.label) (aqui: \(here))"
        }
        let labels = versions.prefix(3).map(\.label).joined(separator: ", ")
        let more = versions.count > 3 ? "…" : ""
        return "\(storeName) tem \(versions.count) outras versões: \(labels)\(more)"
    }
}
