import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. É o valor
/// padrão de `PostQueue.init`, pra uma fila construída sem pensar em disco (testes, previews)
/// nunca escrever em disco por acidente. A produção passa `SwiftDataPostHistoryPersistence`
/// explicitamente.
@MainActor
final class InMemoryPostHistoryPersistence: PostHistoryPersisting {
    /// Mais recente primeiro, mesma ordem que `SwiftDataPostHistoryPersistence.loadEntries()`
    /// devolve (por `completedAt` decrescente).
    private var entries: [PostHistoryEntry] = []

    // Default-argument expressions em `PostQueue.init` são avaliados fora do MainActor — sem
    // isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadEntries() -> [PostHistoryEntry] {
        entries
    }

    func insert(_ entry: PostHistoryEntry) {
        entries.insert(entry, at: 0)
    }

    func clear() {
        entries.removeAll()
    }
}
