import Foundation

/// Uma das ações da barra de baixo na seleção múltipla de "publicados". "Aplicar desconto" só
/// aparece quando a seleção tem algum produto que pede desconto — os outros não têm preço sugerido
/// pra aplicar (ver `AccountPublishedTabView.availableBulkActions`). "Postar em" abre antes o menu
/// das outras lojas (`opensMenu`), e a confirmação dela é a de `PostToOtherStoreCopy`, já com a loja
/// escolhida — os textos de confirmação daqui não valem pra ela. "Repostar" não entra aqui: em
/// publicados fica só no menu "..." de cada produto (a aba "inativos" mantém o dela, em
/// `InactiveBulkAction`).
nonisolated enum PublishedBulkAction: SelectionBarAction, CaseIterable, Sendable {
    case applyDiscount
    case postToOtherStore
    case inactivate
    case delete

    var id: Self { self }

    /// Rótulo curto, embaixo do ícone na barra.
    var label: String {
        switch self {
        case .applyDiscount: "desconto"
        case .postToOtherStore: "postar em"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    /// No iPhone, com até quatro ações lado a lado, "postar em" encurta.
    var compactLabel: String {
        self == .postToOtherStore ? "postar" : label
    }

    var opensMenu: Bool { self == .postToOtherStore }

    /// Mesmos ícones do menu "..." de cada linha, pra reconhecer de longe qual ação é.
    var systemImage: String {
        switch self {
        case .applyDiscount: "tag"
        case .postToOtherStore: PostToOtherStoreCopy.systemImage
        case .inactivate: "archivebox"
        case .delete: "trash"
        }
    }

    var role: SelectionBarActionRole {
        switch self {
        case .applyDiscount: .decision
        case .delete: .destructive
        case .postToOtherStore, .inactivate: .standard
        }
    }

    var isDestructive: Bool { self == .delete }

    /// O tipo de ação que cada produto vira na fila — pra confirmação dizer o ritmo do grupo dele.
    /// `nil` em "desconto", que não passa pela fila.
    var queueKind: PostQueueItem.Kind? {
        switch self {
        case .applyDiscount: nil
        case .postToOtherStore: .post
        case .inactivate: .inactivate
        case .delete: .delete
        }
    }

    /// Botão de confirmar do alerta.
    var confirmationButtonLabel: String {
        switch self {
        case .applyDiscount: "aplicar desconto"
        case .postToOtherStore: "postar"
        case .inactivate: "inativar"
        case .delete: "apagar"
        }
    }

    func confirmationTitle(count: Int) -> String {
        let products = count == 1 ? "1 produto" : "\(count) produtos"
        return switch self {
        case .applyDiscount: "aplicar desconto e megafonar \(products)?"
        case .postToOtherStore: "postar \(products) em outra loja?"
        case .inactivate: "inativar \(products)?"
        case .delete: "apagar \(products)?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .applyDiscount:
            "cada produto vai pro preço com desconto sugerido pelo megafone, e é megafonado na hora."
        case .postToOtherStore:
            "cada um vira um anúncio novo na loja escolhida e entra na fila de ações. os anúncios daqui continuam como estão."
        case .inactivate:
            "cada anúncio selecionado entra na fila de ações e sai da vitrine de publicados — dá pra reativar depois direto no enjoei."
        case .delete:
            "ação irreversível: cada anúncio selecionado entra na fila de ações e é apagado do enjoei de vez, sem chance de recuperar."
        }
    }
}
