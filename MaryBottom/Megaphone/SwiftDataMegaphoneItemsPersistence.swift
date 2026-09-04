import Foundation
import SwiftData

/// Guarda a lista de produtos carregada por um megafone de uma conta com SwiftData — mesmo
/// raciocínio de `SwiftDataInactiveProductsPersistence`: cada produto vira seu próprio registro,
/// campo por campo, num `ModelContainer` próprio dessa conta (ver `PerAccountModelContainer`).
@MainActor
final class SwiftDataMegaphoneItemsPersistence: MegaphoneItemsPersisting {
    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.schemaVersion`.
    private static let schemaVersion = 3
    private static let schemaVersionDefaultsKeyPrefix = "megaphone.schemaVersion."

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

    func loadItems() -> [MegaphoneItem] {
        migrateLegacyItemsIfNeeded()
        let descriptor = FetchDescriptor<MegaphoneItemRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asMegaphoneItem)
    }

    func saveItems(_ items: [MegaphoneItem]) {
        deleteRecords()
        for (index, item) in items.enumerated() {
            context.insert(MegaphoneItemRecord(sortIndex: index, item: item))
        }
        try? context.save()
    }

    /// Busca por `title` direto no SwiftData: `#Predicate` filtra pela coluna e `fetchLimit` corta
    /// o resultado. Devolve só os ids — o `status`/exposição salvos aqui nunca refletem uma
    /// megafonagem em andamento, então não tem por que reconstruir o `MegaphoneItem` inteiro aqui
    /// só pra quem chama jogar fora e recruzar com a lista ao vivo de qualquer jeito.
    func searchProductIDs(matching query: String, limit: Int) -> [Int] {
        var descriptor: FetchDescriptor<MegaphoneItemRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<MegaphoneItemRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        } else {
            descriptor = FetchDescriptor<MegaphoneItemRecord>(
                predicate: #Predicate { $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.productID)
    }

    func clearItems() {
        deleteRecords()
        try? context.save()
    }

    private func deleteRecords() {
        try? context.delete(model: MegaphoneItemRecord.self)
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsMegaphoneItemsPersistence`
    /// antigo não perde o cache na atualização.
    private func migrateLegacyItemsIfNeeded() {
        let key = "megaphone.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([MegaphoneItem].self, from: data) else { return }
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
