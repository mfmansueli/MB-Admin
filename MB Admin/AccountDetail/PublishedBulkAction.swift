import Foundation

/// Uma das ações da barra de baixo na seleção múltipla de "publicados". "Aplicar desconto" só
/// aparece quando a seleção tem algum produto que pede desconto — os outros não têm preço sugerido
/// pra aplicar (ver `AccountPublishedTabView.availableBulkActions`).
nonisolated enum PublishedBulkAction: SelectionBarAction, CaseIterable, Sendable {
    case applyDiscount
    case repost
    case inactivate
    case delete

    var id: Self { self }

    /// Rótulo curto, embaixo do ícone na barra.
    var label: String {
        switch self {
        case .applyDiscount: "desconto"
        case .repost: "repostar"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    /// Mesmos ícones do menu "..." de cada linha, pra reconhecer de longe qual ação é.
    var systemImage: String {
        switch self {
        case .applyDiscount: "tag"
        case .repost: "doc.on.doc"
        case .inactivate: "archivebox"
        case .delete: "trash"
        }
    }

    var role: SelectionBarActionRole {
        switch self {
        case .applyDiscount: .decision
        case .delete: .destructive
        case .repost, .inactivate: .standard
        }
    }

    var isDestructive: Bool { self == .delete }

    /// Botão de confirmar do alerta.
    var confirmationButtonLabel: String {
        switch self {
        case .applyDiscount: "aplicar desconto"
        case .repost: "repostar"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    func confirmationTitle(count: Int) -> String {
        let products = count == 1 ? "1 produto" : "\(count) produtos"
        return switch self {
        case .applyDiscount: "aplicar desconto e megafonar \(products)?"
        case .repost: "repostar \(products)?"
        case .inactivate: "inativar \(products)?"
        case .delete: "apagar \(products)?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .applyDiscount:
            "cada produto vai pro preço com desconto sugerido pelo megafone, e é megafonado na hora."
        case .repost:
            "entra na fila de ações, reaproveitando título, descrição, preço e fotos de cada um — acompanhe o andamento por lá."
        case .inactivate:
            "cada anúncio selecionado entra na fila de ações e sai da vitrine de publicados — dá pra reativar depois direto no enjoei."
        case .delete:
            "ação irreversível: cada anúncio selecionado entra na fila de ações e é apagado do enjoei de vez, sem chance de recuperar."
        }
    }
}
