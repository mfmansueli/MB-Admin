import Foundation

/// Quem sabe guardar a lista de produtos inativos entre uma abertura do app e outra — pra não
/// buscar a loja inteira de novo toda vez, só quando a aba "inativos" é aberta sem nada carregado
/// ainda. Protocolo para os testes não dependerem de `UserDefaults`.
@MainActor
protocol InactiveProductsPersisting {
    func loadItems(accountID: EnjoeiAccountID) -> [InactiveProduct]
    func saveItems(_ items: [InactiveProduct], accountID: EnjoeiAccountID)
    func clearItems(accountID: EnjoeiAccountID)
}
