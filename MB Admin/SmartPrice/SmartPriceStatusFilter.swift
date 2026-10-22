import Foundation

/// Filtro da aba "sem preço esperto", por `SmartPriceProduct.statusText` — o rótulo que o Enjoei já
/// calcula pra cada anúncio. Casa por trecho do texto (não igualdade exata) pra não quebrar se o
/// Enjoei mudar a pontuação/sufixo do rótulo (ex.: "preço alto, venda lenta") sem mudar a ideia por
/// trás dele.
///
/// Os casos estão na ordem da fileira de cápsulas embaixo das abas (`AccountDetailView`) — "preço
/// atual" primeiro, que é o padrão: o uso de sempre é ativar o preço esperto em todos desse grupo.
/// `String` pra ser guardado por conta no `UserDefaults`, como `AccountProductFilter`.
nonisolated enum SmartPriceStatusFilter: String, CaseIterable, Hashable, Sendable {
    case current
    case high
    case low
    case all

    static let defaultFilter = SmartPriceStatusFilter.current

    /// Chave do `UserDefaults` com o filtro escolhido de uma conta.
    static func storageKey(for accountID: EnjoeiAccountID) -> String {
        "accountDetail.smartPriceFilter.\(accountID)"
    }

    var label: String {
        switch self {
        case .all: "todos"
        case .current: "preço atual"
        case .high: "preço alto, venda lenta"
        case .low: "preço baixo"
        }
    }

    func matches(_ product: SmartPriceProduct) -> Bool {
        switch self {
        case .all:
            true
        case .current:
            product.statusText?.localizedCaseInsensitiveContains("atual") == true
        case .high:
            product.statusText?.localizedCaseInsensitiveContains("alto") == true
        case .low:
            product.statusText?.localizedCaseInsensitiveContains("baixo") == true
        }
    }

    /// Quantos dos produtos caem neste filtro — o número de cada cápsula.
    func count(in products: [SmartPriceProduct]) -> Int {
        products.count(where: matches)
    }

    /// Cor da bolinha da cápsula: a que o Enjoei manda (`statusColor`) pro primeiro produto deste
    /// status. `nil` em "todos" (não é um status) ou sem nenhum produto pra dizer a cor.
    func dotColorHex(in products: [SmartPriceProduct]) -> String? {
        guard self != .all else { return nil }
        return products.first { matches($0) && $0.statusColor != nil }?.statusColor
    }

    /// Os que ainda contam nas cápsulas: tira quem acabou de ganhar o preço esperto por aqui — a
    /// lista só some deles no próximo carregamento (a linha fica "preço esperto ativado").
    static func stillWithoutSmartPrice(
        _ products: [SmartPriceProduct],
        activationStatuses: [Int: MegaphoneStatus]
    ) -> [SmartPriceProduct] {
        products.filter { !$0.smartPriceEnabled && activationStatuses[$0.id] != .succeeded }
    }
}
