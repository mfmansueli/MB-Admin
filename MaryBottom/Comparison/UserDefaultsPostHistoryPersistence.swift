import Foundation

/// Guarda o histórico de ações da fila em `UserDefaults`, como JSON — uma chave só, compartilhada
/// entre todas as contas (cada entrada já carrega o id/nome de origem e destino, então não precisa
/// de uma chave por conta como `UserDefaultsMegaphoneItemsPersistence`).
@MainActor
final class UserDefaultsPostHistoryPersistence: PostHistoryPersisting {
    private static let key = "postHistory.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadEntries() -> [PostHistoryEntry] {
        // Nada salvo ainda, ou dado que não decodifica mais: começa vazio — o histórico volta a
        // crescer a partir da próxima ação, sem alarme nenhum.
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PostHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [PostHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
