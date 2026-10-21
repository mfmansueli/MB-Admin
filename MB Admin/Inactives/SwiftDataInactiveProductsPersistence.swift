import Foundation
import SwiftData

/// Guarda a lista de produtos inativos de uma conta com SwiftData — cada produto vira seu próprio
/// registro em disco, campo por campo (sem JSON envolvido depois que o dado sai da rede, ver
/// `InactiveProductRecord`), num `ModelContainer` próprio dessa conta (ver
/// `PerAccountModelContainer`) — nenhuma consulta aqui precisa filtrar por conta porque não existe
/// registro de outra conta nesse arquivo.
@MainActor
final class SwiftDataInactiveProductsPersistence: InactiveProductsPersisting {
    /// Versão do esquema — bump quando `InactiveProductRecord` muda de forma incompatível com
    /// registros já salvos (ex.: trocar `payload` codificado por colunas nativas). Sem isso,
    /// registros do esquema antigo ficariam com os campos novos zerados/vazios (o valor padrão de
    /// uma migração automática do SwiftData, que não sabe reconstruir os campos novos a partir de
    /// um `payload` que não existe mais) e apareceriam na tela como produtos sem título/preço até o
    /// próximo carregamento — em vez disso, descarta tudo uma vez e deixa o próximo `load()`
    /// regravar do zero.
    private static let schemaVersion = 3
    private static let schemaVersionDefaultsKeyPrefix = "inactive.schemaVersion."

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

    func loadItems() -> [InactiveProduct] {
        migrateLegacyItemsIfNeeded()
        let descriptor = FetchDescriptor<InactiveProductRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asInactiveProduct)
    }

    /// Sem tentar diferenciar o que mudou de uma página pra outra: apaga tudo que essa conta tinha
    /// e regrava do zero — mesmo comportamento (e mesmo custo, já que a lista vem inteira da rede a
    /// cada carregamento) da versão em `UserDefaults`, só que fora do plist compartilhado. Usado só
    /// pela migração da chave legada — o carregamento de verdade usa `appendPage` (ver
    /// `InactiveProductsLoader.run()`), pra a busca já enxergar cada página assim que ela chega.
    func saveItems(_ items: [InactiveProduct]) {
        deleteRecords()
        insert(items, startingAt: 0)
    }

    func appendPage(_ items: [InactiveProduct], startingAt offset: Int) {
        insert(items, startingAt: offset)
    }

    /// Busca por `title` direto no SwiftData: `#Predicate` filtra pela coluna e `fetchLimit` corta
    /// o resultado — sem `JSONDecoder` nenhum, os campos já são colunas nativas do registro.
    func search(matching query: String, limit: Int) -> [InactiveProduct] {
        var descriptor: FetchDescriptor<InactiveProductRecord>
        if query.isEmpty {
            descriptor = FetchDescriptor<InactiveProductRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        } else {
            descriptor = FetchDescriptor<InactiveProductRecord>(
                predicate: #Predicate { $0.title.localizedStandardContains(query) },
                sortBy: [SortDescriptor(\.sortIndex)]
            )
        }
        descriptor.fetchLimit = limit
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map(\.asInactiveProduct)
    }

    func removeItem(productID: Int) {
        try? context.delete(model: InactiveProductRecord.self, where: #Predicate { $0.productID == productID })
        try? context.save()
    }

    func clearItems() {
        deleteRecords()
        try? context.save()
    }

    private func insert(_ items: [InactiveProduct], startingAt offset: Int) {
        for (index, item) in items.enumerated() {
            context.insert(InactiveProductRecord(sortIndex: offset + index, product: item))
        }
        try? context.save()
    }

    private func deleteRecords() {
        try? context.delete(model: InactiveProductRecord.self)
    }

    /// Uma vez por conta: quem tinha lista salva pelo `UserDefaultsInactiveProductsPersistence`
    /// antigo não perde o cache na atualização — lê a chave legada daquela conta, se existir,
    /// importa como registros novos e apaga a chave (sem isso, rodaria de novo a cada abertura).
    private func migrateLegacyItemsIfNeeded() {
        let key = "inactive.items.\(accountID)"
        guard let data = defaults.data(forKey: key) else { return }
        defer { defaults.removeObject(forKey: key) }
        guard let legacyItems = try? JSONDecoder().decode([InactiveProduct].self, from: data) else { return }
        saveItems(legacyItems)
    }

    /// Uma vez por conta: descarta os registros dessa conta se vieram de um esquema anterior — não
    /// dá pra reconstruir os campos novos a partir de um `payload`/coluna que não existe mais no
    /// arquivo antigo. Chave de versão por conta (não global) porque cada conta tem seu próprio
    /// arquivo desde a migração pra `PerAccountModelContainer` (ver esse tipo).
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
