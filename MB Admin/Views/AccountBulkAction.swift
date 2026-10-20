import SwiftUI

/// Ação escolhida pro botão de confirmar da seleção múltipla, no filtro "todos os anúncios" de
/// `AccountPublishedTabView`.
enum AccountBulkAction: BulkActionOption {
    case repost
    case inactivate
    case delete

    var label: String {
        switch self {
        case .repost: "repostar"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    /// Mesmos ícones do menu "..." de cada linha, pro botão de confirmar em massa reconhecer de
    /// longe (junto com a cor) qual ação está selecionada.
    var systemImage: String {
        switch self {
        case .repost: "doc.on.doc.fill"
        case .inactivate: "archivebox.fill"
        case .delete: "trash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .repost: .accentColor
        case .inactivate: .secondary
        case .delete: .red
        }
    }
}
