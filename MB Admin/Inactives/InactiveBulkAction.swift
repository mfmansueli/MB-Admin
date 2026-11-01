import Foundation

/// Uma das ações da barra de baixo na seleção múltipla de "inativos": repostar (cria de novo, sem
/// mexer no status de inativo) ou apagar (some do enjoei de vez). As duas entram na fila de ações,
/// depois de confirmar.
///
/// Sem "ativar" (voltar o mesmo anúncio pra vitrine) — tirado a pedido do usuário, aqui e no menu
/// de cada linha (`InactiveProductRowView`). A fila continua sabendo ativar (`PostQueue`), pra
/// terminar o que já estava nela antes disso.
nonisolated enum InactiveBulkAction: SelectionBarAction, CaseIterable, Sendable {
    case repost
    case delete

    var id: Self { self }

    var label: String {
        switch self {
        case .repost: "repostar"
        case .delete: "apagar"
        }
    }

    /// Mesmos ícones do menu "..." de cada linha.
    var systemImage: String {
        switch self {
        case .repost: "doc.on.doc"
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
        case .delete: .delete
        }
    }

    /// Botão de confirmar do alerta.
    var confirmationButtonLabel: String {
        switch self {
        case .repost: "repostar"
        case .delete: PermanentDeleteCopy.confirmButtonLabel
        }
    }

    func confirmationTitle(count: Int) -> String {
        let products = count == 1 ? "1 produto" : "\(count) produtos"
        return switch self {
        case .repost: "repostar \(products)?"
        case .delete: PermanentDeleteCopy.title(productCount: count)
        }
    }

    /// Apagar avisa quantos anúncios somem da loja de vez (`PermanentDeleteCopy`); repostar não muda
    /// com a quantidade.
    func confirmationMessage(count: Int) -> String {
        switch self {
        case .repost:
            "entra na fila de ações, reaproveitando título, descrição, preço e fotos de cada um — acompanhe o andamento por lá."
        case .delete:
            PermanentDeleteCopy.message(productCount: count)
        }
    }
}
