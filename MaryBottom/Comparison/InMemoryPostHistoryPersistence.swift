import Foundation

/// Persistência que não persiste nada de verdade — some quando o processo termina. É o valor
/// padrão de `PostQueue.init`, pra uma fila construída sem pensar em disco (testes, previews)
/// nunca escrever em `UserDefaults` por acidente. A produção passa `UserDefaultsPostHistoryPersistence`
/// explicitamente.
@MainActor
final class InMemoryPostHistoryPersistence: PostHistoryPersisting {
    private var entries: [PostHistoryEntry] = []

    // Default-argument expressions em `PostQueue.init` são avaliados fora do MainActor — sem
    // isso, o compilador recusa construir o valor padrão inline.
    nonisolated init() {}

    func loadEntries() -> [PostHistoryEntry] {
        entries
    }

    func save(_ entries: [PostHistoryEntry]) {
        self.entries = entries
    }
}
