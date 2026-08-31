import Foundation

/// Guarda a lista de produtos carregada por um megafone em `UserDefaults`, como JSON — uma chave
/// por conta.
@MainActor
final class UserDefaultsMegaphoneItemsPersistence: MegaphoneItemsPersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadItems(accountID: EnjoeiAccountID) -> [MegaphoneItem] {
        // Nada salvo ainda, ou dado que não decodifica mais: começa vazio — a tela busca a loja
        // sozinha nesse caso, igual à primeira abertura do app.
        guard let data = defaults.data(forKey: key(for: accountID)) else { return [] }
        return (try? JSONDecoder().decode([MegaphoneItem].self, from: data)) ?? []
    }

    func saveItems(_ items: [MegaphoneItem], accountID: EnjoeiAccountID) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    func clearItems(accountID: EnjoeiAccountID) {
        defaults.removeObject(forKey: key(for: accountID))
    }

    private func key(for accountID: EnjoeiAccountID) -> String {
        "megaphone.items.\(accountID)"
    }
}
