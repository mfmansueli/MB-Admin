import Foundation

/// Guarda os itens pendentes da fila em `UserDefaults`, como JSON — uma chave só, compartilhada
/// entre todas as contas (mesmo raciocínio de `UserDefaultsPostHistoryPersistence`: cada item já
/// carrega o id/nome de origem e destino, então não precisa de uma chave por conta).
@MainActor
final class UserDefaultsPostQueueItemsPersistence: PostQueueItemsPersisting {
    private static let key = "postQueue.pendingItems.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadItems() -> [PostQueueItem] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PostQueueItem].self, from: data)) ?? []
    }

    func saveItems(_ items: [PostQueueItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
