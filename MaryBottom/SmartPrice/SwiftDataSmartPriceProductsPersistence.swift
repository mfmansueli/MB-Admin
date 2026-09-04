import Foundation
import SwiftData

/// Guarda a lista de produtos sem preço esperto com SwiftData — mesmo raciocínio de
/// `SwiftDataInactiveProductsPersistence`: cada produto vira seu próprio registro em disco, campo
/// por campo, sem JSON envolvido depois que o dado sai da rede (ver `SmartPriceProductRecord`).
@MainActor
final class SwiftDataSmartPriceProductsPersistence: SmartPriceProductsPersisting {
    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.schemaVersion` — bump quando
    /// `SmartPriceProductRecord` muda de forma incompatível com registros já salvos.
    private static let schemaVersion = 2
    private static let schemaVersionDefaultsKey = "smartPrice.schemaVersion"

    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SharedModelContainer.shared, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
        wipeStaleSchemaIfNeeded()
    }

    func loadItems(accountID: EnjoeiAccountID) -> [SmartPriceProduct] {
        migrateLegacyItemsIfNeeded(accountID: accountID)
        let descriptor = FetchDescriptor<SmartPriceProductRecord>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asSmartPriceProduct)
    }

    /// Usado só pela migração da chave legada — o carregamento de verdade usa `appendPage` (ver
    /// `SmartPriceProductsLoader.run()`), pra a busca já enxergar cada página assim que ela chega.
    /// Sem título resolvido aqui (a migração não tem acesso à aba "publicados") — `backfillTitles`
    /// conserta assim que o loader tiver um resolvedor de verdade.
    func saveItems(_ items: [SmartPriceProduct], accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        insert(items, startingAt: 0, accountID: accountID, titleResolver: { _ in nil })
    }

    func appendPage(
        _ items: [SmartPriceProduct],
        startingAt offset: Int,
        accountID: EnjoeiAccountID,
        titleResolver: (Int) -> String?
    ) {
        insert(items, startingAt: offset, accountID: accountID, titleResolver: titleResolver)
    }

    func backfillTitles(resolver: (Int) -> String?, accountID: EnjoeiAccountID) {
        let descriptor = FetchDescriptor<SmartPriceProductRecord>(predicate: #Predicate { $0.accountID == accountID })
        guard let records = try? context.fetch(descriptor) else { return }
        var changed = false
        for record in records {
            guard let resolvedTitle = resolver(record.productID), resolvedTitle != record.title else { continue }
            record.title = resolvedTitle
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Busca por `title` direto no SwiftData: `#Predicate` filtra pela coluna e `fetchLimit` corta
    /// o resultado — sem `JSONDecoder` nenhum, os campos já são colunas nativas do registro.
    func search(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [SmartPriceProduct] {
        var descriptor: FetchDescriptor<SmartPriceProductRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<SmartPriceProductRecord>(
                predicate: #Predicate { $0.accountID == accountID },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        } else {
            descriptor = FetchDescriptor<SmartPriceProductRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asSmartPriceProduct)
    }

    func clearItems(accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        try? context.save()
    }

    private func insert(
        _ items: [SmartPriceProduct],
        startingAt offset: Int,
        accountID: EnjoeiAccountID,
        titleResolver: (Int) -> String?
    ) {
        for (index, item) in items.enumerated() {
            let record = SmartPriceProductRecord(
                accountID: accountID,
                sortIndex: offset + index,
                title: titleResolver(item.id) ?? "",
                product: item
            )
            context.insert(record)
        }
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

    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.wipeStaleSchemaIfNeeded()`.
    private func wipeStaleSchemaIfNeeded() {
        guard defaults.integer(forKey: Self.schemaVersionDefaultsKey) < Self.schemaVersion else { return }
        try? context.delete(model: SmartPriceProductRecord.self)
        try? context.save()
        defaults.set(Self.schemaVersion, forKey: Self.schemaVersionDefaultsKey)
    }
}
