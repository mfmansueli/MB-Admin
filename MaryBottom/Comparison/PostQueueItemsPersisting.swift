import Foundation

/// Quem sabe guardar os itens ainda pendentes da fila de ações, entre uma abertura do app e
/// outra — só os pendentes (ver `PostQueue.persistPendingItems`), nunca os já concluídos (esses já
/// ficam no histórico, `PostHistoryPersisting`). Protocolo para os testes não dependerem de
/// `UserDefaults`.
@MainActor
protocol PostQueueItemsPersisting {
    func loadItems() -> [PostQueueItem]
    func saveItems(_ items: [PostQueueItem])
}
