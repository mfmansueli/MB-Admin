import Foundation

/// Uma ação da barra de baixo de uma seleção múltipla (`SelectionActionBar`) — cada tela define o
/// próprio enum, só com as ações que fazem sentido ali (ex.: `PublishedBulkAction`,
/// `InactiveBulkAction`).
protocol SelectionBarAction: Identifiable, Hashable {
    /// Rótulo curto, embaixo do ícone na barra.
    var label: String { get }
    var systemImage: String { get }
    var role: SelectionBarActionRole { get }
}
