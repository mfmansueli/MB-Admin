import Foundation

/// Guarda a lista de contas em `UserDefaults`, como JSON.
@MainActor
final class UserDefaultsAccountsPersistence: AccountsPersisting {
    private static let key = "accounts.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAccounts() -> [AccountRecord] {
        // Nada salvo ainda, ou dado que não decodifica mais: começa vazio, sem alarme — não é
        // diferente de "ninguém logado" na primeira abertura do app.
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([AccountRecord].self, from: data)) ?? []
    }

    func save(_ accounts: [AccountRecord]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
