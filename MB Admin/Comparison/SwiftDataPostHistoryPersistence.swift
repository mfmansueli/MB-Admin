import Foundation
import SwiftData

/// Guarda o histórico de ações da fila com SwiftData — ao contrário do antigo
/// `UserDefaultsPostHistoryPersistence` (uma chave só com o array inteiro serializado, reescrito
/// por completo a cada entrada nova), cada `insert` grava só o registro novo. Sem isso, um
/// histórico de uso real (várias contas, meses de uso) ia ficando cada vez mais pesado de gravar
/// só porque uma entrada a mais entrou no fim da lista.
@MainActor
final class SwiftDataPostHistoryPersistence: PostHistoryPersisting {
    /// Chave legada de `UserDefaultsPostHistoryPersistence` — migrada uma única vez para o
    /// `ModelContainer` na primeira execução depois do update, e removida na sequência.
    private static let legacyDefaultsKey = "postHistory.v1"

    /// Teto de entradas trazidas pra memória em `loadEntries()` — sem isso, um histórico de uso
    /// real (meses de uso, várias contas) deixa o boot do app cada vez mais lento porque decodifica
    /// o JSON de toda entrada já registrada, mesmo as que ninguém vai rolar até ver.
    private static let maxLoadedEntries = 300

    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SharedModelContainer.shared, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
        migrateLegacyEntriesIfNeeded()
    }

    func loadEntries() -> [PostHistoryEntry] {
        var descriptor = FetchDescriptor<PostHistoryRecord>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.maxLoadedEntries
        guard let records = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return records.compactMap { try? decoder.decode(PostHistoryEntry.self, from: $0.payload) }
    }

    func insert(_ entry: PostHistoryEntry) {
        guard let payload = try? JSONEncoder().encode(entry) else { return }
        context.insert(PostHistoryRecord(id: entry.id, completedAt: entry.completedAt, payload: payload))
        try? context.save()
    }

    func clear() {
        try? context.delete(model: PostHistoryRecord.self)
        try? context.save()
    }

    /// Uma vez só: quem tinha histórico salvo pelo `UserDefaultsPostHistoryPersistence` antigo não
    /// perde nada na atualização — lê a chave legada, se existir, importa cada entrada como um
    /// `PostHistoryRecord` e apaga a chave (sem isso, rodaria de novo a cada abertura do app).
    private func migrateLegacyEntriesIfNeeded() {
        guard let data = defaults.data(forKey: Self.legacyDefaultsKey) else { return }
        defer { defaults.removeObject(forKey: Self.legacyDefaultsKey) }
        guard let legacyEntries = try? JSONDecoder().decode([PostHistoryEntry].self, from: data) else { return }
        let encoder = JSONEncoder()
        for entry in legacyEntries {
            guard let payload = try? encoder.encode(entry) else { continue }
            context.insert(PostHistoryRecord(id: entry.id, completedAt: entry.completedAt, payload: payload))
        }
        try? context.save()
    }
}
