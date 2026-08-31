import Foundation

/// Quem sabe guardar a lista de produtos que um megafone já carregou, entre uma abertura do app e
/// outra — pra não buscar a loja inteira de novo toda vez, só quando o usuário força o recarregar.
/// Protocolo para os testes não dependerem de `UserDefaults`.
@MainActor
protocol MegaphoneItemsPersisting {
    func loadItems(accountID: EnjoeiAccountID) -> [MegaphoneItem]
    func saveItems(_ items: [MegaphoneItem], accountID: EnjoeiAccountID)
    func clearItems(accountID: EnjoeiAccountID)
}
