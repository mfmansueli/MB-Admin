import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. É o valor
/// padrão de `PostQueue.init`, pra uma fila construída sem pensar em disco (testes, previews)
/// nunca escrever em disco por acidente. A produção passa `UserDefaultsPostQueueItemsPersistence`
/// explicitamente.
@MainActor
final class InMemoryPostQueueItemsPersistence: PostQueueItemsPersisting {
    private var items: [PostQueueItem] = []

    // Default-argument expressions em `PostQueue.init` são avaliadas fora do MainActor — sem
    // isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadItems() -> [PostQueueItem] {
        items
    }

    func saveItems(_ items: [PostQueueItem]) {
        self.items = items
    }
}
