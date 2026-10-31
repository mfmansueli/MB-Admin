import Foundation

/// Uma ação da barra de baixo de uma seleção múltipla (`SelectionActionBar`) — cada tela define o
/// próprio enum, só com as ações que fazem sentido ali (ex.: `PublishedBulkAction`,
/// `InactiveBulkAction`).
protocol SelectionBarAction: Identifiable, Hashable {
    /// Rótulo curto, embaixo do ícone na barra.
    var label: String { get }
    /// Rótulo no iPhone, onde a barra chega a ter cinco ações lado a lado — o mesmo `label` quando
    /// ele já é curto o bastante.
    var compactLabel: String { get }
    var systemImage: String { get }
    var role: SelectionBarActionRole { get }
    /// Abre um menu (o `menuContent` da barra) em vez de chamar `onSelect` direto — pra ações que
    /// ainda precisam de uma escolha antes da confirmação, como a loja de destino de "postar em".
    var opensMenu: Bool { get }
}

extension SelectionBarAction {
    var compactLabel: String { label }
    var opensMenu: Bool { false }
}
