import Foundation

/// Uma das ações da barra de baixo na seleção múltipla de "inativos": repostar (cria de novo, sem
/// mexer no status de inativo), ativar (volta o mesmo anúncio pra vitrine de publicados) ou apagar
/// (some do enjoei de vez). Todas entram na fila de ações, depois de confirmar.
nonisolated enum InactiveBulkAction: SelectionBarAction, CaseIterable, Sendable {
    case repost
    case activate
    case delete

    var id: Self { self }

    var label: String {
        switch self {
        case .repost: "repostar"
        case .activate: "ativar"
        case .delete: "apagar"
        }
    }

    /// Mesmos ícones do menu "..." de cada linha.
    var systemImage: String {
        switch self {
        case .repost: "doc.on.doc"
        case .activate: "tray.and.arrow.up"
        case .delete: "trash"
        }
    }

    var role: SelectionBarActionRole {
        self == .delete ? .destructive : .standard
    }

    var isDestructive: Bool { self == .delete }

    /// O tipo de ação que cada produto vira na fila — pra confirmação dizer o ritmo do grupo dele.
    var queueKind: PostQueueItem.Kind {
        switch self {
        case .repost: .post
        case .activate: .activate
        case .delete: .delete
        }
    }

    /// Botão de confirmar do alerta.
    var confirmationButtonLabel: String {
        switch self {
        case .repost: "repostar"
        case .activate: "ativar"
        case .delete: PermanentDeleteCopy.confirmButtonLabel
        }
    }

    func confirmationTitle(count: Int) -> String {
        let products = count == 1 ? "1 produto" : "\(count) produtos"
        return switch self {
        case .repost: "repostar \(products)?"
        case .activate: "ativar \(products) de novo?"
        case .delete: PermanentDeleteCopy.title(productCount: count)
        }
    }

    /// Apagar avisa quantos anúncios somem da loja de vez (`PermanentDeleteCopy`); as outras não
    /// mudam com a quantidade.
    func confirmationMessage(count: Int) -> String {
        switch self {
        case .repost:
            "entra na fila de ações, reaproveitando título, descrição, preço e fotos de cada um — acompanhe o andamento por lá."
        case .activate:
            "cada anúncio selecionado entra na fila de ações e volta pra vitrine de publicados."
        case .delete:
            PermanentDeleteCopy.message(productCount: count)
        }
    }
}
