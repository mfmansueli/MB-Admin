import Foundation
@testable import MB_Admin

/// Substitui o `UserDefaults` nos testes de contas.
@MainActor
final class InMemoryAccountsPersistence: AccountsPersisting {
    private(set) var saveCalls: [[AccountRecord]] = []
    var stored: [AccountRecord]

    init(stored: [AccountRecord] = []) {
        self.stored = stored
    }

    func loadAccounts() -> [AccountRecord] { stored }

    func save(_ accounts: [AccountRecord]) {
        stored = accounts
        saveCalls.append(accounts)
    }
}
