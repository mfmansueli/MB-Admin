import Foundation
import SwiftData

/// Guarda a lista de produtos sem preço esperto de uma conta com SwiftData — mesmo raciocínio de
/// `SwiftDataInactiveProductsPersistence`: cada produto vira seu próprio registro, campo por campo,
/// num `ModelContainer` próprio dessa conta (ver `PerAccountModelContainer`).
@MainActor
final class SwiftDataSmartPriceProductsPersistence: SmartPriceProductsPersisting {
    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.schemaVersion`.
    private static let schemaVersion = 3
    private static let schemaVersionDefaultsKeyPrefix = "smartPrice.schemaVersion."

    private let context: ModelContext
    private let defaults: UserDefaults
    private let accountID: EnjoeiAccountID

    /// `container`: `nil` em produção usa o container próprio dessa conta (ver
    /// `PerAccountModelContainer`); testes passam um container em memória explícito, isolado do
    /// disco de verdade.
    init(accountID: EnjoeiAccountID, container: ModelContainer? = nil, defaults: UserDefaults = .standard) {
        self.accountID = accountID
        context = ModelContext(container ?? PerAccountModelContainer.shared(for: accountID))
        self.defaults = defaults
        wipeStaleSchemaIfNeeded()
    }

    func loadItems() -> [SmartPriceProduct] {
        migrateLegacyItemsIfNeeded()
        let descriptor = FetchDescriptor<SmartPriceProductRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asSmartPriceProduct)
    }

    /// Usado só pela migração da chave legada — o carregamento de verdade usa `appendPage` (ver
    /// `SmartPriceProductsLoader.run()`), pra a busca já enxergar cada página assim que ela chega.
    /// Sem título resolvido aqui (a migração não tem acesso à aba "publicados") — `backfillTitles`
    /// conserta assim que o loader tiver um resolvedor de verdade.
    func saveItems(_ items: [SmartPriceProduct]) {
        deleteRecords()
        insert(items, startingAt: 0, titleResolver: { _ in nil })
    }

    func appendPage(_ items: [SmartPriceProduct], startingAt offset: Int, titleResolver: (Int) -> String?) {
        insert(items, startingAt: offset, titleResolver: titleResolver)
    }

    func backfillTitles(resolver: (Int) -> String?) {
        let descriptor = FetchDescriptor<SmartPriceProductRecord>()
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
    func search(matching query: String, limit: Int) -> [SmartPriceProduct] {
        var descriptor: FetchDescriptor<SmartPriceProductRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<SmartPriceProductRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        } else {
            descriptor = FetchDescriptor<SmartPriceProductRecord>(
                predicate: #Predicate { $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asSmartPriceProduct)
    }

    func clearItems() {
        deleteRecords()
        try? context.save()
    }

    private func insert(_ items: [SmartPriceProduct], startingAt offset: Int, titleResolver: (Int) -> String?) {
        for (index, item) in items.enumerated() {
            let record = SmartPriceProductRecord(
                sortIndex: offset + index,
                title: titleResolver(item.id) ?? "",
                product: item
            )
            context.insert(record)
        }
        try? context.save()
    }

    private func deleteRecords() {
        try? context.delete(model: SmartPriceProductRecord.self)
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsSmartPriceProductsPersistence`
    /// antigo não perde o cache na atualização.
    private func migrateLegacyItemsIfNeeded() {
        let key = "smartPrice.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([SmartPriceProduct].self, from: data) else { return }
        saveItems(legacyItems)
    }

    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.wipeStaleSchemaIfNeeded()`.
    private func wipeStaleSchemaIfNeeded() {
        let key = schemaVersionDefaultsKey
        guard defaults.integer(forKey: key) < Self.schemaVersion else { return }
        deleteRecords()
        try? context.save()
        defaults.set(Self.schemaVersion, forKey: key)
    }

    private var schemaVersionDefaultsKey: String {
        "\(Self.schemaVersionDefaultsKeyPrefix)\(accountID)"
    }
}
