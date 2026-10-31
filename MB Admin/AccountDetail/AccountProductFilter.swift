import Foundation

/// Filtro da lista de publicados, em `AccountPublishedTabView` (escolhido na fileira de cápsulas de
/// `AccountDetailView`) — "todos os anúncios" ou só os que o megafone está sugerindo desconto.
/// `String` (não só `Equatable`): guardado por conta no `UserDefaults`, em `AccountDetailView` — sem
/// raw value compatível, a escolha não sobreviveria a trocar de conta e voltar.
enum AccountProductFilter: String, CaseIterable {
    case all
    case discountOnly

    /// Chave do `UserDefaults` com o filtro escolhido de uma conta.
    static func storageKey(for accountID: EnjoeiAccountID) -> String {
        "accountDetail.filter.\(accountID)"
    }

    /// Nome do filtro na fileira de cápsulas embaixo das abas.
    var label: String {
        switch self {
        case .all: "todos os anúncios"
        case .discountOnly: "só os que pedem desconto"
        }
    }
}
