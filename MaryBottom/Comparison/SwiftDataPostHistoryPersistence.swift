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

    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SwiftDataPostHistoryPersistence.makeSharedContainer(), defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
        migrateLegacyEntriesIfNeeded()
    }

    // `nonisolated`: usado como expressão de argumento padrão em `init`, que é avaliada fora do
    // MainActor — mesma razão do `nonisolated init()` de `InMemoryPostHistoryPersistence`.
    nonisolated static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([PostHistoryRecord.self])
        // Esquema fixo, conhecido em tempo de compilação — não tem como falhar em runtime a não
        // ser por disco cheio/corrompido, quando não haveria app funcional mesmo (mesmo padrão de
        // `URL(string:)!` em `EnjoeiAPI`).
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }

    func loadEntries() -> [PostHistoryEntry] {
        let descriptor = FetchDescriptor<PostHistoryRecord>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
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
