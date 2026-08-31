import Foundation

/// Guarda a lista de produtos inativos em `UserDefaults`, como JSON — uma chave por conta, mesmo
/// padrão de `UserDefaultsMegaphoneItemsPersistence`.
@MainActor
final class UserDefaultsInactiveProductsPersistence: InactiveProductsPersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadItems(accountID: EnjoeiAccountID) -> [InactiveProduct] {
        guard let data = defaults.data(forKey: key(for: accountID)) else { return [] }
        return (try? JSONDecoder().decode([InactiveProduct].self, from: data)) ?? []
    }

    func saveItems(_ items: [InactiveProduct], accountID: EnjoeiAccountID) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    func clearItems(accountID: EnjoeiAccountID) {
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func key(for accountID: EnjoeiAccountID) -> String {
        "inactive.items.\(accountID)"
    }
}
