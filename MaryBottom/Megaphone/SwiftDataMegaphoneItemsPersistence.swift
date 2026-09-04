import Foundation
import SwiftData

/// Guarda a lista de produtos carregada por um megafone com SwiftData — mesmo raciocínio de
/// `SwiftDataInactiveProductsPersistence`: cada produto vira seu próprio registro em disco, campo
/// por campo, sem JSON envolvido depois que o dado sai da rede (ver `MegaphoneItemRecord`).
@MainActor
final class SwiftDataMegaphoneItemsPersistence: MegaphoneItemsPersisting {
    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.schemaVersion` — bump quando
    /// `MegaphoneItemRecord` muda de forma incompatível com registros já salvos.
    private static let schemaVersion = 2
    private static let schemaVersionDefaultsKey = "megaphone.schemaVersion"

    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SharedModelContainer.shared, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
        wipeStaleSchemaIfNeeded()
    }

    func loadItems(accountID: EnjoeiAccountID) -> [MegaphoneItem] {
        migrateLegacyItemsIfNeeded(accountID: accountID)
        let descriptor = FetchDescriptor<MegaphoneItemRecord>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asMegaphoneItem)
    }

    func saveItems(_ items: [MegaphoneItem], accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        for (index, item) in items.enumerated() {
            context.insert(MegaphoneItemRecord(accountID: accountID, sortIndex: index, item: item))
        }
        try? context.save()
    }

    /// Busca por `title` direto no SwiftData: `#Predicate` filtra pela coluna e `fetchLimit` corta
    /// o resultado. Devolve só os ids — o `status`/exposição salvos aqui nunca refletem uma
    /// megafonagem em andamento, então não tem por que reconstruir o `MegaphoneItem` inteiro aqui
    /// só pra quem chama jogar fora e recruzar com a lista ao vivo de qualquer jeito.
    func searchProductIDs(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [Int] {
        var descriptor: FetchDescriptor<MegaphoneItemRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<MegaphoneItemRecord>(
                predicate: #Predicate { $0.accountID == accountID },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        } else {
            descriptor = FetchDescriptor<MegaphoneItemRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.productID)
    }

    func clearItems(accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        try? context.save()
    }

    private func deleteRecords(accountID: EnjoeiAccountID) {
        try? context.delete(model: MegaphoneItemRecord.self, where: #Predicate { $0.accountID == accountID })
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsMegaphoneItemsPersistence`
    /// antigo não perde o cache na atualização.
    private func migrateLegacyItemsIfNeeded(accountID: EnjoeiAccountID) {
        let key = "megaphone.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([MegaphoneItem].self, from: data) else { return }
        saveItems(legacyItems, accountID: accountID)
    }

    /// Mesmo raciocínio de `SwiftDataInactiveProductsPersistence.wipeStaleSchemaIfNeeded()`.
    private func wipeStaleSchemaIfNeeded() {
        guard defaults.integer(forKey: Self.schemaVersionDefaultsKey) < Self.schemaVersion else { return }
        try? context.delete(model: MegaphoneItemRecord.self)
        try? context.save()
        defaults.set(Self.schemaVersion, forKey: Self.schemaVersionDefaultsKey)
    }
}
