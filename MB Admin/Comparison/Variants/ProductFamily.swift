import Foundation

/// Um produto com várias versões — anúncios (de uma ou das duas lojas) que dividem a mesma foto —,
/// com o que existe de cada versão em cada loja. É o que responde "quais versões estão numa loja e
/// não na outra" sem o usuário precisar abrir par por par.
nonisolated struct ProductFamily: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let photoPublicID: String?
    /// Os eixos que mudam entre as versões (o que cada linha mostra), na ordem de `VariantDimension`.
    let dimensions: [VariantDimension]
    let versions: [ProductFamilyVersion]

    var versionsOnlyInA: Int { versions.count { $0.presence == .onlyInA } }
    var versionsOnlyInB: Int { versions.count { $0.presence == .onlyInB } }
    var hasMissingVersions: Bool { versionsOnlyInA + versionsOnlyInB > 0 }

    /// "3 versões · 1 só em antonia · 1 só em loja B".
    func summary(accountAName: String, accountBName: String) -> String {
        var parts = [versions.count == 1 ? "1 versão" : "\(versions.count) versões"]
        if versionsOnlyInA > 0 { parts.append("\(versionsOnlyInA) só em \(accountAName)") }
        if versionsOnlyInB > 0 { parts.append("\(versionsOnlyInB) só em \(accountBName)") }
        return parts.joined(separator: " · ")
    }

    func matchesSearch(_ text: String) -> Bool {
        title.localizedCaseInsensitiveContains(text)
            || versions.contains { version in
                [version.productA, version.productB].contains { $0?.title.localizedCaseInsensitiveContains(text) == true }
            }
    }
}
