import Foundation

/// Quanto de uma seção da aba "publicados" está marcado na seleção — decide o círculo à esquerda do
/// cabeçalho (`PublishedSectionHeader`) e o rótulo da cápsula à direita ("selecionar os 3"/"desmarcar
/// os 3"). Só existe no modo de seleção; fora dele o cabeçalho recebe `nil` — por isso os casos não
/// se chamam `none`/`all`: `.none` num `SectionSelectionState?` se confundiria com `Optional.none`.
nonisolated enum SectionSelectionState: Equatable, Sendable {
    case noneSelected
    case someSelected
    case allSelected

    /// Seção vazia conta como `.noneSelected` — não tem o que desmarcar.
    init(sectionIDs: [Int], selectedIDs: Set<Int>) {
        let selectedCount = sectionIDs.count(where: selectedIDs.contains)
        if selectedCount == 0 {
            self = .noneSelected
        } else if selectedCount == sectionIDs.count {
            self = .allSelected
        } else {
            self = .someSelected
        }
    }

    /// Mesmos símbolos do círculo de cada linha (`MegaphoneRowView`), mais o "–" de quando só
    /// alguns estão marcados.
    var symbolName: String {
        switch self {
        case .noneSelected: "circle"
        case .someSelected: "minus.circle.fill"
        case .allSelected: "checkmark.circle.fill"
        }
    }

    /// "selecionar os 3" — ou "desmarcar os 3" com a seção inteira marcada. Diferente do
    /// "selecionar tudo" da barra de cima (que vale pra lista inteira), aqui a quantidade deixa
    /// claro que é só desta seção.
    func toggleAllLabel(count: Int) -> String {
        let verb = self == .allSelected ? "desmarcar" : "selecionar"
        let articleAndCount = count == 1 ? "o 1" : "os \(count.formatted())"
        return "\(verb) \(articleAndCount)"
    }

    /// Versão do VoiceOver, que não vê o cabeçalho ao lado: "selecionar os 3 de pedem desconto".
    func toggleAllAccessibilityLabel(count: Int, sectionTitle: String) -> String {
        "\(toggleAllLabel(count: count)) de \(sectionTitle)"
    }
}
