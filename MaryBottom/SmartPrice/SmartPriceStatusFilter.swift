import Foundation

/// Filtro da aba "sem preço esperto", por `SmartPriceProduct.statusText` — o rótulo que o Enjoei já
/// calcula pra cada anúncio. Casa por trecho do texto (não igualdade exata) pra não quebrar se o
/// Enjoei mudar a pontuação/sufixo do rótulo (ex.: "preço alto, venda lenta") sem mudar a ideia por
/// trás dele.
nonisolated enum SmartPriceStatusFilter: CaseIterable, Hashable {
    case all
    case current
    case high
    case low

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
}
