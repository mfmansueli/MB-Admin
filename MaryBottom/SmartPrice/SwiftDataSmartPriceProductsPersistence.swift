import Foundation
import SwiftData

/// Guarda a lista de produtos sem preço esperto com SwiftData — mesmo raciocínio de
/// `SwiftDataInactiveProductsPersistence`: cada produto vira seu próprio registro em disco, em vez
/// de uma chave só com o array inteiro serializado no plist compartilhado do `UserDefaults`.
@MainActor
final class SwiftDataSmartPriceProductsPersistence: SmartPriceProductsPersisting {
    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SwiftDataSmartPriceProductsPersistence.sharedContainer, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
    }

    nonisolated static let sharedContainer: ModelContainer = {
        let schema = Schema([SmartPriceProductRecord.self])
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }()

    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct] {
        migrateLegacyItemsIfNeeded(accountID: accountID)
        let descriptor = FetchDescriptor<SmartPriceProductRecord>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        let decoder = JSONDecoder()
        return records.compactMap { try? decoder.decode(SmartPriceProduct.self, from: $0.payload) }
    }

    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        let encoder = JSONEncoder()
        for (index, item) in items.enumerated() {
            guard let payload = try? encoder.encode(item) else { continue }
            context.insert(SmartPriceProductRecord(accountID: accountID, sortIndex: index, payload: payload))
        }
        try? context.save()
    }

    func clearItems(accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        try? context.save()
    }

    private func deleteRecords(accountID: EnjoeiAccountID) {
        try? context.delete(model: SmartPriceProductRecord.self, where: #Predicate { $0.accountID == accountID })
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsSmartPriceProductsPersistence`
    /// antigo não perde o cache na atualização.
    private func migrateLegacyItemsIfNeeded(accountID: EnjoeiAccountID) {
        let key = "smartPrice.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([SmartPriceProduct].self, from: data) else { return }
        saveItems(legacyItems, accountID: accountID)
    }
}
