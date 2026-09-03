import Foundation

/// Quem sabe guardar o histórico de ações já concluídas da fila, entre uma abertura do app e
/// outra. Protocolo para os testes não dependerem de `UserDefaults`.
@MainActor
protocol PostHistoryPersisting {
    func loadEntries() -> [PostHistoryEntry]
    func save(_ entries: [PostHistoryEntry])
}
