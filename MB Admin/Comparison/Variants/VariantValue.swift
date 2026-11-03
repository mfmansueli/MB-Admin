import Foundation

/// Um valor de atributo de variante: `canonical` é o que se compara ("16", "rodio", "450" mm),
/// `display` é como a tela mostra ("aro 16", "ródio", "45 cm"). Dois valores são iguais pelo
/// `canonical` — "aro 16" e "tam. 16" são o mesmo tamanho.
nonisolated struct VariantValue: Hashable, Sendable {
    let canonical: String
    let display: String

    static func == (lhs: VariantValue, rhs: VariantValue) -> Bool { lhs.canonical == rhs.canonical }

    func hash(into hasher: inout Hasher) { hasher.combine(canonical) }
}
