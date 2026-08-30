import Foundation

/// Quem sabe guardar quais contas existem entre uma abertura do app e outra. Protocolo para os
/// testes não dependerem de `UserDefaults`.
@MainActor
protocol AccountsPersisting {
    func loadAccounts() -> [AccountRecord]
    func save(_ accounts: [AccountRecord])
}
