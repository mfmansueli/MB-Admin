import Foundation
import SwiftData

/// Guarda a lista de produtos inativos com SwiftData — ao contrário do antigo
/// `UserDefaultsInactiveProductsPersistence` (uma chave por conta com o array inteiro serializado
/// dentro do plist compartilhado do `UserDefaults`, que fica inteiro carregado na memória do
/// processo o app inteiro), cada produto vira seu próprio registro em disco, campo por campo — sem
/// JSON envolvido depois que o dado sai da rede (ver `InactiveProductRecord`).
@MainActor
final class SwiftDataInactiveProductsPersistence: InactiveProductsPersisting {
    /// Versão do esquema — bump quando `InactiveProductRecord` muda de forma incompatível com
    /// registros já salvos (ex.: trocar `payload` codificado por colunas nativas). Sem isso,
    /// registros do esquema antigo ficariam com os campos novos zerados/vazios (o valor padrão de
    /// uma migração automática do SwiftData, que não sabe reconstruir os campos novos a partir de
    /// um `payload` que não existe mais) e apareceriam na tela como produtos sem título/preço até o
    /// próximo carregamento — em vez disso, descarta tudo uma vez e deixa o próximo `load()`
    /// regravar do zero.
    private static let schemaVersion = 2
    private static let schemaVersionDefaultsKey = "inactive.schemaVersion"

    private let context: ModelContext
    private let defaults: UserDefaults

    init(container: ModelContainer = SharedModelContainer.shared, defaults: UserDefaults = .standard) {
        context = ModelContext(container)
        self.defaults = defaults
        wipeStaleSchemaIfNeeded()
    }

    func loadItems(accountID: EnjoeiAccountID) -> [InactiveProduct] {
        migrateLegacyItemsIfNeeded(accountID: accountID)
        let descriptor = FetchDescriptor<InactiveProductRecord>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asInactiveProduct)
    }

    /// Sem tentar diferenciar o que mudou de uma página pra outra: apaga tudo que essa conta tinha
    /// e regrava do zero — mesmo comportamento (e mesmo custo, já que a lista vem inteira da rede a
    /// cada carregamento) da versão em `UserDefaults`, só que fora do plist compartilhado. Usado só
    /// pela migração da chave legada — o carregamento de verdade usa `appendPage` (ver
    /// `InactiveProductsLoader.run()`), pra a busca já enxergar cada página assim que ela chega.
    func saveItems(_ items: [InactiveProduct], accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        insert(items, startingAt: 0, accountID: accountID)
    }

    func appendPage(_ items: [InactiveProduct], startingAt offset: Int, accountID: EnjoeiAccountID) {
        insert(items, startingAt: offset, accountID: accountID)
    }

    /// Busca por `title` direto no SwiftData: `#Predicate` filtra pela coluna e `fetchLimit` corta
    /// o resultado — sem `JSONDecoder` nenhum, os campos já são colunas nativas do registro.
    func search(matching query: String, accountID: EnjoeiAccountID, limit: Int) -> [InactiveProduct] {
        var descriptor: FetchDescriptor<InactiveProductRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<InactiveProductRecord>(
                predicate: #Predicate { $0.accountID == accountID },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        } else {
            descriptor = FetchDescriptor<InactiveProductRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asInactiveProduct)
    }

    func clearItems(accountID: EnjoeiAccountID) {
        deleteRecords(accountID: accountID)
        try? context.save()
    }

    private func insert(_ items: [InactiveProduct], startingAt offset: Int, accountID: EnjoeiAccountID) {
        for (index, item) in items.enumerated() {
            context.insert(InactiveProductRecord(accountID: accountID, sortIndex: offset + index, product: item))
        }
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

    /// Uma vez só, pro processo inteiro (não por conta — todo `InactiveProductRecord` de todas as
    /// contas veio do esquema antigo se veio de antes dessa versão): descarta tudo, já que não dá
    /// pra reconstruir os campos novos a partir de um `payload` que não existe mais no registro
    /// migrado automaticamente pelo SwiftData. Cada loader detecta a lista vazia no próximo
    /// `AccountDetailView` aberto e recarrega da rede sozinho — é só cache.
    private func wipeStaleSchemaIfNeeded() {
        guard defaults.integer(forKey: Self.schemaVersionDefaultsKey) < Self.schemaVersion else { return }
        try? context.delete(model: InactiveProductRecord.self)
        try? context.save()
        defaults.set(Self.schemaVersion, forKey: Self.schemaVersionDefaultsKey)
    }
}
