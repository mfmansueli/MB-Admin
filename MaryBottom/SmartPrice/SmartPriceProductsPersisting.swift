import Foundation

/// Quem sabe guardar a lista de produtos sem preço esperto entre uma abertura do app e outra —
/// mesmo raciocínio de `InactiveProductsPersisting`. Protocolo para os testes não dependerem de
/// `UserDefaults`.
@MainActor
protocol SmartPriceProductsPersisting {
    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct]
    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID)
    func clearItems(accountID: EnjoeiAccountID)
}
