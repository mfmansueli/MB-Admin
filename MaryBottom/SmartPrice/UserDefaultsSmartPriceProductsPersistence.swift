import Foundation

/// Guarda a lista de produtos sem preço esperto em `UserDefaults`, como JSON — uma chave por conta,
/// mesmo padrão de `UserDefaultsInactiveProductsPersistence`.
@MainActor
final class UserDefaultsSmartPriceProductsPersistence: SmartPriceProductsPersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct] {
        guard let data = defaults.data(forKey: key(for: accountID)) else { return [] }
        return (try? JSONDecoder().decode([SmartPriceProduct].self, from: data)) ?? []
    }

    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    func clearItems(accountID: EnjoeiAccountID) {
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func key(for accountID: EnjoeiAccountID) -> String {
        "smartPrice.items.\(accountID)"
    }
}
