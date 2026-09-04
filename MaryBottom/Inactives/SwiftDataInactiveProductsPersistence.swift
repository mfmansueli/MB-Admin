import Foundation
import SwiftData

/// Guarda a lista de produtos inativos com SwiftData — ao contrário do antigo
/// `UserDefaultsInactiveProductsPersistence` (uma chave por conta com o array inteiro serializado
/// dentro do plist compartilhado do `UserDefaults`, que fica inteiro carregado na memória do
/// processo o app inteiro), cada produto vira seu próprio registro em disco. Mesmo raciocínio de
/// `SwiftDataPostHistoryPersistence`.
@MainActor
final class SwiftDataInactiveProductsPersistence: InactiveProductsPersisting {
    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SwiftDataInactiveProductsPersistence.sharedContainer, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
    }

    // Mesmo raciocínio de `SwiftDataPostHistoryPersistence.sharedContainer` — computado uma vez só
    // e cacheado, pra duas instâncias sem `container` explícito nunca brigarem por lock do SQLite.
    nonisolated static let sharedContainer: ModelContainer = {
        let schema = Schema([InactiveProductRecord.self])
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }()

    func loadItems(accountID: EnjoeiAccountID) -> [InactiveProduct] {
        migrateLegacyItemsIfNeeded(accountID: accountID)
        let descriptor = FetchDescriptor<InactiveProductRecord>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return records.compactMap { try? decoder.decode(InactiveProduct.self, from: $0.payload) }
    }

    /// Sem tentar diferenciar o que mudou de uma página pra outra: apaga tudo que essa conta tinha
    /// e regrava do zero — mesmo comportamento (e mesmo custo, já que a lista vem inteira da rede a
    /// cada carregamento) da versão em `UserDefaults`, só que fora do plist compartilhado.
    func saveItems(_ items: [InactiveProduct], accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        let encoder = JSONEncoder()
        for (index, item) in items.enumerated() {
            guard let payload = try? encoder.encode(item) else { continue }
            context.insert(InactiveProductRecord(accountID: accountID, sortIndex: index, payload: payload))
        }
        try? context.save()
    }

    func clearItems(accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        try? context.save()
    }

    private func deleteRecords(accountID: EnjoeiAccountID) {
        try? context.delete(model: InactiveProductRecord.self, where: #Predicate { $0.accountID == accountID })
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsInactiveProductsPersistence`
    /// antigo não perde o cache na atualização — lê a chave legada daquela conta, se existir,
    /// importa como registros novos e apaga a chave (sem isso, rodaria de novo a cada abertura).
    private func migrateLegacyItemsIfNeeded(accountID: EnjoeiAccountID) {
        let key = "inactive.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([InactiveProduct].self, from: data) else { return }
        saveItems(legacyItems, accountID: accountID)
    }
}
