import Foundation

/// Quem sabe guardar o histórico de ações já concluídas da fila, entre uma abertura do app e
/// outra. `insert`/`clear` em vez de "salvar a lista inteira" de propósito: o histórico só cresce
/// (nunca é reescrito por completo), então a persistência de verdade (`SwiftDataPostHistoryPersistence`)
/// consegue gravar cada entrada nova sem reler/reescrever tudo que já existia. Protocolo para os
/// testes não dependerem do armazenamento de disco de verdade.
@MainActor
protocol PostHistoryPersisting {
    func loadEntries() -> [PostHistoryEntry]
    func insert(_ entry: PostHistoryEntry)
    func clear()
}
